from __future__ import annotations

from fastapi import APIRouter, HTTPException
from datetime import datetime
from bson import ObjectId
from app.core.security import decode_token
from app.core.db import col
from app.services.notify_service import send_push_to_user

router = APIRouter(prefix="/api/notifications", tags=["notifications"])


@router.get("")
async def list_notifications(token: str, limit: int = 50):
    """List notifications for the authenticated user (newest first)."""
    try:
        user_id = decode_token(token)["sub"]
    except Exception:
        raise HTTPException(401, "Invalid token")

    cursor = col("notifications").find({"userId": user_id}).sort("createdAt", -1).limit(limit)
    items = await cursor.to_list(limit)
    for it in items:
        it["_id"] = str(it["_id"])
    return items


@router.get("/unread_count")
async def unread_count(token: str):
    """Return count of unread notifications."""
    try:
        user_id = decode_token(token)["sub"]
    except Exception:
        raise HTTPException(401, "Invalid token")

    count = await col("notifications").count_documents({"userId": user_id, "read": False})
    return {"count": count}


@router.post("/mark_read/{notification_id}")
async def mark_read(notification_id: str, token: str):
    """Mark a single notification as read."""
    try:
        user_id = decode_token(token)["sub"]
    except Exception:
        raise HTTPException(401, "Invalid token")

    result = await col("notifications").update_one(
        {"_id": ObjectId(notification_id), "userId": user_id},
        {"$set": {"read": True}},
    )
    if result.matched_count == 0:
        raise HTTPException(404, "Notification not found")
    return {"ok": True}


@router.post("/mark_all_read")
async def mark_all_read(token: str):
    """Mark all notifications for the user as read."""
    try:
        user_id = decode_token(token)["sub"]
    except Exception:
        raise HTTPException(401, "Invalid token")

    await col("notifications").update_many(
        {"userId": user_id, "read": False},
        {"$set": {"read": True}},
    )
    return {"ok": True}


from pydantic import BaseModel as _BaseModel

class CheckTireAgeReq(_BaseModel):
    carId: str
    position: str
    dotCode: str

class CheckTreadAgeReq(_BaseModel):
    carId: str
    position: str


@router.post("/check_tire_age")
async def check_tire_age(req: CheckTireAgeReq, token: str):
    """Create tire-age-expired notification if not already notified recently."""
    try:
        user_id = decode_token(token)["sub"]
    except Exception:
        raise HTTPException(401, "Invalid token")

    # Deduplicate: check if we already sent this notification in the last 7 days
    from datetime import timedelta
    recent = await col("notifications").find_one({
        "userId": user_id,
        "type": "tire_age_expired",
        "body": {"$regex": req.position},
        "createdAt": {"$gte": datetime.utcnow() - timedelta(days=7)},
    })
    if recent:
        return {"ok": True, "skipped": True}

    title = "⚠️ ยางหมดอายุ!"
    body = f"ยางตำแหน่ง {req.position} (DOT: {req.dotCode}) อายุเกิน 5 ปี ควรเปลี่ยนยางใหม่"
    await create_notification(user_id, "tire_age_expired", title, body)
    return {"ok": True}


@router.post("/check_tread_age")
async def check_tread_age(req: CheckTreadAgeReq, token: str):
    """Create tread-depth-reminder notification if not already notified recently."""
    try:
        user_id = decode_token(token)["sub"]
    except Exception:
        raise HTTPException(401, "Invalid token")

    from datetime import timedelta
    recent = await col("notifications").find_one({
        "userId": user_id,
        "type": "tread_depth_reminder",
        "body": {"$regex": req.position},
        "createdAt": {"$gte": datetime.utcnow() - timedelta(days=7)},
    })
    if recent:
        return {"ok": True, "skipped": True}

    title = "📸 อัพเดตดอกยาง"
    body = f"ข้อมูลดอกยางตำแหน่ง {req.position} ไม่ได้อัพเดตเกิน 3 เดือน กรุณาถ่ายภาพดอกยางใหม่"
    await create_notification(user_id, "tread_depth_reminder", title, body)
    return {"ok": True}


async def create_notification(user_id: str, ntype: str, title: str, body: str):
    """Helper: insert a notification document AND send push to the device."""
    doc = {
        "userId": user_id,
        "type": ntype,
        "title": title,
        "body": body,
        "read": False,
        "createdAt": datetime.utcnow(),
    }
    await col("notifications").insert_one(doc)

    # ส่ง push notification ไปที่มือถือด้วย
    try:
        await send_push_to_user(user_id, title, body)
    except Exception:
        pass  # push อาจล้มเหลวได้ (เช่น ยังไม่ได้ลง OneSignal) — ไม่ block

