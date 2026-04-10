from fastapi import APIRouter
from pydantic import BaseModel
from datetime import datetime
from app.core.db import col
from app.core.security import create_token

router = APIRouter(prefix="/api/auth", tags=["auth"])

class AnonymousReq(BaseModel):
    deviceId: str

@router.post("/anonymous")
async def anonymous_login(req: AnonymousReq):
    users = col("users")
    user = await users.find_one({"type": "anonymous", "deviceId": req.deviceId})
    if not user:
        doc = {"type": "anonymous", "deviceId": req.deviceId, "createdAt": datetime.utcnow()}
        r = await users.insert_one(doc)
        user_id = str(r.inserted_id)
    else:
        user_id = str(user["_id"])

    token = create_token(sub=user_id, role="user")
    return {"userId": user_id, "token": token}
