from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from datetime import datetime
from app.core.config import settings
from app.core.security import create_token
from app.core.deps import require_admin
from app.core.db import col
from app.services.notify_service import send_push_to_user, send_push_to_all
from app.routes.notifications import create_notification

router = APIRouter(prefix="/api/admin", tags=["admin"])

class UserPushReq(BaseModel):
    userId: str
    title: str
    body: str

class AllPushReq(BaseModel):
    title: str
    body: str

@router.get("/users")
async def list_users(token: str):
    require_admin(token)
    items = await col("users").find({}, {"password": 0}).to_list(100)
    for it in items:
        it["_id"] = str(it["_id"])
    return items

@router.post("/notify/user")
async def admin_notify_user(req: UserPushReq, token: str):
    require_admin(token)
    await create_notification(req.userId, "admin_message", req.title, req.body)
    return {"ok": True}

@router.post("/notify/all")
async def admin_notify_all(req: AllPushReq, token: str):
    require_admin(token)
    # Save notification + push for ALL users
    cursor = col("users").find({}, {"_id": 1})
    users = await cursor.to_list(10000)
    for u in users:
        await create_notification(str(u["_id"]), "admin_message", req.title, req.body)
    return {"ok": True}

class AdminLoginReq(BaseModel):
    username: str
    password: str

@router.post("/login")
async def admin_login(req: AdminLoginReq):
    if req.username != settings.ADMIN_USERNAME or req.password != settings.ADMIN_PASSWORD:
        raise HTTPException(401, "Wrong credentials")
    token = create_token(sub=req.username, role="admin")
    return {"token": token}

@router.get("/formula/active")
async def get_active_formula():
    f = await col("formula_configs").find_one({"active": True}, sort=[("version", -1)])
    if not f:
        return {}
    f["_id"] = str(f["_id"])
    return f

class FormulaReq(BaseModel):
    name: str
    minDepthMm: float
    newDepthMm: float
    wearRateMmPer10000Km: float
    warningRemainingKm: int
    replaceRemainingKm: int

@router.post("/formula")
async def create_formula(req: FormulaReq, token: str):
    require_admin(token)
    last = await col("formula_configs").find_one({}, sort=[("version", -1)])
    next_ver = int(last["version"]) + 1 if last else 1

    await col("formula_configs").update_many({"active": True}, {"$set": {"active": False}})
    doc = req.model_dump()
    doc.update({"version": next_ver, "active": True, "updatedAt": datetime.utcnow()})
    r = await col("formula_configs").insert_one(doc)
    return {"id": str(r.inserted_id), "version": next_ver}
