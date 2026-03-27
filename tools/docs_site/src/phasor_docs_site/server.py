from __future__ import annotations

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .config import SitePaths


def create_app(paths: SitePaths) -> FastAPI:
    app = FastAPI(title="phasor docs preview")

    @app.get("/favicon.ico", include_in_schema=False)
    def favicon() -> FileResponse:
        return FileResponse(
            paths.output_root / "static" / "images" / "favicon.svg",
            media_type="image/svg+xml",
        )

    app.mount("/", StaticFiles(directory=str(paths.output_root), html=True), name="site")
    return app
