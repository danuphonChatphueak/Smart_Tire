from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from datetime import datetime
from app.core.security import decode_token
from app.core.db import col

router = APIRouter(prefix="/api/device", tags=["device"])

class RegisterPushReq(BaseModel):
    oneSignalId: str

@router.post("/register_push")
async def register_push(req: RegisterPushReq, token: str):
    try:
        user_id = decode_token(token)["sub"]
    except Exception:
        raise HTTPException(401, "Invalid token")

    await col("devices").update_one(
        {"userId": user_id},
        {"$set": {"userId": user_id, "oneSignalId": req.oneSignalId, "updatedAt": datetime.utcnow()}},
        upsert=True
    )
    return {"ok": True}
