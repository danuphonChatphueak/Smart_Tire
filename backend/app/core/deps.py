from fastapi import HTTPException
from app.core.security import decode_token

def get_user_id(token: str) -> str:
    try:
        return decode_token(token)["sub"]
    except Exception:
        raise HTTPException(401, "Invalid token")

def require_admin(token: str) -> dict:
    try:
        payload = decode_token(token)
    except Exception:
        raise HTTPException(401, "Invalid token")
    if payload.get("role") != "admin":
        raise HTTPException(403, "Admin only")
    return payload
