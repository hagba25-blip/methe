from fastapi import APIRouter

router = APIRouter(tags=["santé"])


@router.get("/health")
async def health() -> dict:
    return {"status": "ok"}
