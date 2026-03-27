from __future__ import annotations

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from .config import SitePaths


def create_app(paths: SitePaths) -> FastAPI:
    app = FastAPI(title="phasor docs preview")
    app.mount("/", StaticFiles(directory=str(paths.output_root), html=True), name="site")
    return app
