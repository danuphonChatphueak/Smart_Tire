import httpx
from app.core.config import settings
from app.core.db import col

async def send_push_to_user(user_id: str, title: str, body: str, data: dict | None = None):
    if settings.PUSH_PROVIDER != "onesignal":
        return

    device = await col("devices").find_one({"userId": user_id})
    if not device or not device.get("oneSignalId"):
        return

    url = "https://onesignal.com/api/v1/notifications"
    payload = {
        "app_id": settings.ONESIGNAL_APP_ID,
        "include_player_ids": [device["oneSignalId"]],
        "headings": {"en": title, "th": title},
        "contents": {"en": body, "th": body},
        "data": data or {},
    }
    headers = {
        "Authorization": f"Basic {settings.ONESIGNAL_API_KEY}",
        "Content-Type": "application/json",
    }

    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.post(url, json=payload, headers=headers)
        r.raise_for_status()

async def send_push_to_all(title: str, body: str, data: dict | None = None):
    if settings.PUSH_PROVIDER != "onesignal":
        return

    # Get all unique OneSignal IDs
    cursor = col("devices").find({"oneSignalId": {"$ne": None}})
    items = await cursor.to_list(1000)
    player_ids = list(set([it["oneSignalId"] for it in items if it.get("oneSignalId")]))
    
    if not player_ids:
        return

    url = "https://onesignal.com/api/v1/notifications"
    payload = {
        "app_id": settings.ONESIGNAL_APP_ID,
        "include_player_ids": player_ids,
        "headings": {"en": title, "th": title},
        "contents": {"en": body, "th": body},
        "data": data or {},
    }
    headers = {
        "Authorization": f"Basic {settings.ONESIGNAL_API_KEY}",
        "Content-Type": "application/json",
    }

    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.post(url, json=payload, headers=headers)
        r.raise_for_status()
