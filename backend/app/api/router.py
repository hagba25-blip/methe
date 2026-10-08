from fastapi import APIRouter

from app.api.routes import admin_users, health, locale, me, settings, wallet

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(locale.router)
api_router.include_router(settings.router)
api_router.include_router(me.router)
api_router.include_router(wallet.router)
api_router.include_router(admin_users.router)
