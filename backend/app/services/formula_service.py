from datetime import datetime
from app.core.db import col

DEFAULT_FORMULA = {
    "name": "default_v1",
    "minDepthMm": 1.6,
    "newDepthMm": 8.0,
    "wearRateMmPer10000Km": 1.0,
    "warningRemainingKm": 8000,
    "replaceRemainingKm": 2000,
    "version": 1,
    "active": True,
    "updatedAt": datetime.utcnow(),
}

async def get_active_formula():
    f = await col("formula_configs").find_one({"active": True}, sort=[("version", -1)])
    if not f:
        await col("formula_configs").insert_one(DEFAULT_FORMULA)
        f = await col("formula_configs").find_one({"active": True}, sort=[("version", -1)])
    return f

def calc_remaining_km(depth_mm: float, formula: dict) -> int:
    min_d = float(formula["minDepthMm"])
    wear = float(formula["wearRateMmPer10000Km"])
    remaining_mm = max(0.0, depth_mm - min_d)
    remaining_km = int((remaining_mm / max(wear, 1e-6)) * 10000)
    return max(0, remaining_km)

def status_from_remaining(remaining_km: int, formula: dict) -> str:
    if remaining_km <= int(formula["replaceRemainingKm"]):
        return "REPLACE"
    if remaining_km <= int(formula["warningRemainingKm"]):
        return "WARN"
    return "OK"
