from __future__ import annotations

import base64
import contextlib
import http.server
import json
import os
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path

import websocket

from .config import SitePaths
from .models import ExampleRecord


DEFAULT_CHROME_CANDIDATES = (
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "google-chrome",
    "chromium",
    "chromium-browser",
    "chrome",
)


class StaticSiteHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, directory: str, **kwargs) -> None:
        super().__init__(*args, directory=directory, **kwargs)

    def log_message(self, format: str, *args) -> None:
        return


@dataclass
class ChromeTarget:
    process: subprocess.Popen[bytes]
    port: int
    profile_dir: Path


class CdpClient:
    def __init__(self, ws_url: str, timeout_s: float) -> None:
        self.default_timeout_s = timeout_s
        self.ws = websocket.create_connection(ws_url, timeout=timeout_s)
        self.next_id = 1

    def close(self) -> None:
        with contextlib.suppress(Exception):
            self.ws.close()

    def send(self, method: str, params: dict | None = None, timeout_s: float | None = None) -> dict:
        msg_id = self.next_id
        self.next_id += 1
        self.ws.settimeout(timeout_s if timeout_s is not None else self.default_timeout_s)
        self.ws.send(json.dumps({"id": msg_id, "method": method, "params": params or {}}))
        while True:
            raw = self.ws.recv()
            message = json.loads(raw)
            if message.get("id") == msg_id:
                return message


def capture_example_screenshots(
    paths: SitePaths,
    examples: list[ExampleRecord],
    *,
    only_examples: list[str],
    chrome_bin: Path | None,
    host: str,
    port: int,
    viewport_width: int,
    viewport_height: int,
    settle_seconds: float,
    headed: bool,
    extra_chrome_args: list[str],
) -> int:
    selected = [example for example in examples if example.wasm_supported]
    if only_examples:
        wanted = set(only_examples)
        selected = [example for example in selected if example.name in wanted]
        missing = sorted(wanted - {example.name for example in selected})
        if missing:
            raise RuntimeError(f"unknown or non-wasm examples requested for capture: {', '.join(missing)}")

    if not selected:
        return 0

    output_dir = paths.site_root / "static" / "images" / "examples"
    output_dir.mkdir(parents=True, exist_ok=True)

    with running_static_server(paths.output_root, host, port):
        browser = launch_chrome_for_capture(
            chrome_bin=chrome_bin,
            viewport_width=viewport_width,
            viewport_height=viewport_height,
            headed=headed,
            extra_args=extra_chrome_args,
        )
        try:
            ws_url = choose_page_ws_url(browser.port)
            client = CdpClient(ws_url, timeout_s=max(30.0, settle_seconds + 10.0))
            try:
                return capture_selected_examples(
                    client,
                    selected,
                    output_dir=output_dir,
                    base_url=f"http://{host}:{port}",
                    viewport_width=viewport_width,
                    viewport_height=viewport_height,
                    settle_seconds=settle_seconds,
                )
            finally:
                client.close()
        finally:
            stop_chrome(browser)


def capture_selected_examples(
    client: CdpClient,
    examples: list[ExampleRecord],
    *,
    output_dir: Path,
    base_url: str,
    viewport_width: int,
    viewport_height: int,
    settle_seconds: float,
) -> int:
    for method in ("Page.enable", "Runtime.enable"):
        reply = client.send(method)
        if "error" in reply:
            raise RuntimeError(f"{method} failed: {reply['error']}")

    metrics = client.send(
        "Emulation.setDeviceMetricsOverride",
        {
            "width": viewport_width,
            "height": viewport_height,
            "deviceScaleFactor": 1,
            "mobile": False,
            "screenWidth": viewport_width,
            "screenHeight": viewport_height,
        },
    )
    if "error" in metrics:
        raise RuntimeError(f"failed to set capture viewport: {metrics['error']}")

    count = 0
    for example in examples:
        if not example.live_demo_path:
            raise RuntimeError(
                f"example '{example.name}' does not have a live demo bundle in docs/_build; run `zig build docs` first"
            )
        url = f"{base_url}/{example.live_demo_path}"
        print(f"capturing {example.name}: {url}")
        navigate_to(client, url)
        wait_for_capture_target(client, settle_seconds)
        clip = query_canvas_clip(client)
        if clip is None:
            raise RuntimeError(f"example '{example.name}' did not expose a visible canvas for capture at {url}")
        png_data = capture_png(client, clip)
        (output_dir / f"{example.name}.png").write_bytes(png_data)
        count += 1
    return count


def navigate_to(client: CdpClient, url: str) -> None:
    response = client.send("Page.navigate", {"url": url})
    if "error" in response:
        raise RuntimeError(f"navigate failed for {url}: {response['error']}")


def wait_for_capture_target(client: CdpClient, settle_seconds: float) -> None:
    deadline = time.time() + max(0.5, settle_seconds)
    while time.time() < deadline:
        state = client.send(
            "Runtime.evaluate",
            {"expression": "document.readyState", "returnByValue": True},
        )
        ready_state = state.get("result", {}).get("result", {}).get("value")
        if ready_state == "complete":
            break
        time.sleep(0.1)
    remaining = deadline - time.time()
    if remaining > 0:
        time.sleep(remaining)


def query_canvas_clip(client: CdpClient) -> dict[str, float] | None:
    reply = client.send(
        "Runtime.evaluate",
        {
            "expression": """
(() => {
  const canvas = document.querySelector("canvas");
  if (!canvas) return null;
  const rect = canvas.getBoundingClientRect();
  if (rect.width < 2 || rect.height < 2) return null;
  return {
    x: Math.max(0, rect.x),
    y: Math.max(0, rect.y),
    width: Math.max(1, rect.width),
    height: Math.max(1, rect.height),
    scale: 1,
  };
})()
""".strip(),
            "returnByValue": True,
        },
    )
    if "error" in reply:
        raise RuntimeError(f"capture target query failed: {reply['error']}")
    return reply.get("result", {}).get("result", {}).get("value")


def capture_png(client: CdpClient, clip: dict[str, float]) -> bytes:
    reply = client.send(
        "Page.captureScreenshot",
        {
            "format": "png",
            "captureBeyondViewport": False,
            "clip": clip,
        },
        timeout_s=60.0,
    )
    if "error" in reply:
        raise RuntimeError(f"captureScreenshot failed: {reply['error']}")
    data = reply.get("result", {}).get("data")
    if not data:
        raise RuntimeError("captureScreenshot returned no image data")
    return base64.b64decode(data)


@contextlib.contextmanager
def running_static_server(root: Path, host: str, port: int):
    handler = lambda *args, **kwargs: StaticSiteHandler(*args, directory=str(root), **kwargs)
    server = http.server.ThreadingHTTPServer((host, port), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5.0)


def launch_chrome_for_capture(
    *,
    chrome_bin: Path | None,
    viewport_width: int,
    viewport_height: int,
    headed: bool,
    extra_args: list[str],
) -> ChromeTarget:
    binary = resolve_chrome_binary(chrome_bin)
    profile_dir = Path(tempfile.mkdtemp(prefix="phasor-docs-capture-"))
    port = 9222
    args = [
        binary,
        f"--remote-debugging-port={port}",
        "--remote-allow-origins=*",
        f"--user-data-dir={profile_dir}",
        "--no-first-run",
        "--no-default-browser-check",
        "--mute-audio",
        "--enable-unsafe-webgpu",
        f"--window-size={viewport_width},{viewport_height}",
    ]
    if not headed:
        args.append("--headless=new")
    args.extend(extra_args)
    args.append("about:blank")
    process = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_http_json(f"http://127.0.0.1:{port}/json/version", 15.0)
    return ChromeTarget(process=process, port=port, profile_dir=profile_dir)


def choose_page_ws_url(port: int) -> str:
    targets = wait_http_json(f"http://127.0.0.1:{port}/json/list", 15.0)
    if not isinstance(targets, list):
        raise RuntimeError("Chrome DevTools did not return a target list")
    for target in targets:
        if target.get("type") == "page" and target.get("webSocketDebuggerUrl"):
            return str(target["webSocketDebuggerUrl"])
    raise RuntimeError("could not find a page target in Chrome DevTools")


def stop_chrome(target: ChromeTarget) -> None:
    target.process.terminate()
    with contextlib.suppress(subprocess.TimeoutExpired):
        target.process.wait(timeout=5.0)
    if target.process.poll() is None:
        target.process.kill()
    shutil.rmtree(target.profile_dir, ignore_errors=True)


def resolve_chrome_binary(explicit: Path | None) -> str:
    if explicit is not None:
        return str(explicit)
    if env_binary := os.environ.get("CHROME_BIN"):
        return env_binary
    for candidate in DEFAULT_CHROME_CANDIDATES:
        resolved = shutil.which(candidate) if "/" not in candidate else candidate
        if resolved and Path(resolved).exists():
            return str(resolved)
    raise RuntimeError("could not find a Chrome/Chromium binary; pass --chrome-bin or set CHROME_BIN")


def http_json(url: str) -> dict | list:
    with urllib.request.urlopen(url, timeout=5) as response:
        return json.loads(response.read().decode("utf-8"))


def wait_http_json(url: str, timeout_s: float) -> dict | list:
    deadline = time.time() + timeout_s
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            return http_json(url)
        except Exception as error:  # pragma: no cover - timing-dependent retry path
            last_error = error
            time.sleep(0.2)
    raise RuntimeError(f"timed out waiting for {url}: {last_error}")
