"""Point d'entrée : uvicorn main:app --reload"""

import asyncio
from contextlib import asynccontextmanager, suppress

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import db
from app.api.router import api_router
from app.config import get_settings
from app.draw import engine
from app.security.rate_limit import RateLimitMiddleware


@asynccontextmanager
async def lifespan(_: FastAPI):
    await db.open_pool()
    task = asyncio.create_task(engine.run_forever()) if get_settings().draw_engine_enabled else None
    yield
    if task is not None:
        task.cancel()
        with suppress(asyncio.CancelledError):
            await task
    await db.close_pool()


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="methe API",
        version="0.1.0",
        lifespan=lifespan,
        docs_url="/docs" if settings.app_env != "production" else None,
        redoc_url=None,
    )
    app.add_middleware(RateLimitMiddleware, per_minute=settings.rate_limit_per_minute)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_methods=["GET", "POST", "PATCH"],
        allow_headers=["Authorization", "Content-Type", "Idempotency-Key"],
    )
    app.include_router(api_router)
    return app


app = create_app()
