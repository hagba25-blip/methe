from fastapi import APIRouter

from app.api.routes import admin_deposits, admin_users, admin_withdrawals, deposits, health, locale, me, settings, wallet, withdrawals

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(locale.router)
api_router.include_router(settings.router)
api_router.include_router(me.router)
api_router.include_router(wallet.router)
api_router.include_router(admin_users.router)
api_router.include_router(deposits.router)
api_router.include_router(admin_deposits.router)
api_router.include_router(withdrawals.router)
api_router.include_router(admin_withdrawals.router)
