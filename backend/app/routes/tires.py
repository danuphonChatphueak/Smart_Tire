from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from datetime import datetime
from bson import ObjectId
from app.core.db import col
from app.core.deps import get_user_id

router = APIRouter(prefix="/api/tires", tags=["tires"])

@router.get("")
async def list_tires(carId: str, token: str):
    user_id = get_user_id(token)
    car = await col("cars").find_one({"_id": ObjectId(carId), "userId": user_id})
    if not car:
        raise HTTPException(404, "car not found")

    items = await col("tires").find({"carId": carId}).to_list(50)
    for it in items:
        it["_id"] = str(it["_id"])
    return items

class SwapReq(BaseModel):
    tireAId: str
    tireBId: str

@router.post("/swap")
async def swap_tires(req: SwapReq, token: str):
    user_id = get_user_id(token)

    tireA = await col("tires").find_one({"_id": ObjectId(req.tireAId)})
    tireB = await col("tires").find_one({"_id": ObjectId(req.tireBId)})
    if not tireA or not tireB:
        raise HTTPException(404, "tire not found")
    if tireA["carId"] != tireB["carId"]:
        raise HTTPException(400, "must be same car")

    car = await col("cars").find_one({"_id": ObjectId(tireA["carId"]), "userId": user_id})
    if not car:
        raise HTTPException(403, "forbidden")

    posA, posB = tireA["position"], tireB["position"]
    now = datetime.utcnow()
    
    # Update both tires
    await col("tires").update_one({"_id": tireA["_id"]}, {"$set": {"position": posB, "updatedAt": now}})
    await col("tires").update_one({"_id": tireB["_id"]}, {"$set": {"position": posA, "updatedAt": now}})
    
    return {"ok": True, "swapped": {req.tireAId: posB, req.tireBId: posA}}

@router.delete("/{tire_id}")
async def delete_tire(tire_id: str, token: str):
    user_id = get_user_id(token)
    
    tire = await col("tires").find_one({"_id": ObjectId(tire_id)})
    if not tire:
        raise HTTPException(404, "Tire not found")
        
    # Check car ownership
    car = await col("cars").find_one({"_id": ObjectId(tire["carId"]), "userId": user_id})
    if not car:
        raise HTTPException(403, "Forbidden")

    await col("tires").delete_one({"_id": ObjectId(tire_id)})
    return {"ok": True, "deletedId": tire_id}
