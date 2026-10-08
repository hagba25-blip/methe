from fastapi import APIRouter

from app.api.routes import health, locale, me

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(locale.router)
api_router.include_router(me.router)
