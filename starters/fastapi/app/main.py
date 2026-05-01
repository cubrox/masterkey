import logging
import os

import sentry_sdk
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from app.error_receiver import router as error_router

logger = logging.getLogger("agile_flow")


def _resolve_sentry_dsn() -> str | None:
    """Determine which Sentry DSN to use.

    Priority:
    1. SENTRY_DSN env var (external Sentry or GlitchTip) -- use as-is
    2. Self-DSN constructed from RENDER_EXTERNAL_URL or APP_URL -- events
       go to the app's own /api/error-events endpoint
    3. None -- Sentry disabled (local dev without config)
    """
    external_dsn = os.getenv("SENTRY_DSN")
    if external_dsn:
        return external_dsn

    # Construct a self-referencing DSN so the app captures its own errors
    app_url = os.getenv("RENDER_EXTERNAL_URL") or os.getenv("APP_URL")
    if app_url:
        # Sentry DSN format: https://{key}@{host}/{project_id}
        # The key is ignored by our receiver; project_id is ignored too
        host = app_url.replace("https://", "").replace("http://", "").rstrip("/")
        self_dsn = f"https://self@{host}/api/error-events/0"
        logger.info("No SENTRY_DSN set -- using self-DSN: errors will create GitHub issues automatically")
        return self_dsn

    logger.info("No SENTRY_DSN or RENDER_EXTERNAL_URL set -- Sentry disabled")
    return None


dsn = _resolve_sentry_dsn()
if dsn:
    sentry_sdk.init(dsn=dsn, traces_sample_rate=1.0)

app = FastAPI(title="Agile Flow Starter")
app.include_router(error_router)
templates = Jinja2Templates(directory=os.path.join(os.path.dirname(__file__), "templates"))


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    return templates.TemplateResponse(request, "index.html")


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/error")
async def error():
    raise RuntimeError(
        "Deliberate error for Day 1 workshop exercise — this should appear in Sentry and auto-create a GitHub issue."
    )
