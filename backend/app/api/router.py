from fastapi import APIRouter

from app.api.routes import admin_dashboard, admin_deposits, admin_risk, admin_rounds, admin_users, admin_withdrawals, bets, deposits, health, locale, me, rounds, settings, wallet, withdrawals

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
api_router.include_router(rounds.router)
api_router.include_router(admin_rounds.router)
api_router.include_router(bets.router)
api_router.include_router(admin_dashboard.router)
api_router.include_router(admin_risk.router)
