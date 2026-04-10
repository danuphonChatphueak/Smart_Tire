from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from datetime import datetime
from bson import ObjectId
from app.core.db import col
from app.core.deps import get_user_id

router = APIRouter(prefix="/api/cars", tags=["cars"])

class CarCreate(BaseModel):
    # ผู้ใช้ “ไม่ต้องส่งอะไรมา” ก็ได้
    carName: str | None = None

class CarRename(BaseModel):
    carName: str

async def _next_car_index(user_id: str) -> int:
    # นับจำนวนรถของ user เพื่อสร้างชื่อ default
    cnt = await col("cars").count_documents({"userId": user_id})
    return int(cnt) + 1

@router.post("")
async def create_car(req: CarCreate, token: str):
    user_id = get_user_id(token)

    if req.carName and req.carName.strip():
        name = req.carName.strip()
    else:
        idx = await _next_car_index(user_id)
        name = f"รถคันที่ {idx}"

    doc = {
        "userId": user_id,
        "carName": name,
        "createdAt": datetime.utcnow(),
        "updatedAt": datetime.utcnow(),
    }
    r = await col("cars").insert_one(doc)
    return {"id": str(r.inserted_id), "carName": name}

@router.get("")
async def list_cars(token: str):
    user_id = get_user_id(token)
    items = await col("cars").find({"userId": user_id}).sort([("createdAt", 1)]).to_list(200)
    for it in items:
        it["_id"] = str(it["_id"])
    return items

@router.patch("/{car_id}/rename")
async def rename_car(car_id: str, token: str, req: CarRename):
    user_id = get_user_id(token)
    if not req.carName.strip():
        raise HTTPException(400, "carName required")

    r = await col("cars").update_one(
        {"_id": ObjectId(car_id), "userId": user_id},
        {"$set": {"carName": req.carName.strip(), "updatedAt": datetime.utcnow()}}
    )
    if r.matched_count == 0:
        raise HTTPException(404, "car not found")

    car = await col("cars").find_one({"_id": ObjectId(car_id)})
    car["_id"] = str(car["_id"])
    return car

@router.delete("/{car_id}")
async def delete_car(car_id: str, token: str):
    user_id = get_user_id(token)
    
    # 1. Check ownership
    car = await col("cars").find_one({"_id": ObjectId(car_id), "userId": user_id})
    if not car:
        raise HTTPException(404, "Car not found")

    # 2. Delete car
    await col("cars").delete_one({"_id": ObjectId(car_id)})

    # 3. Delete related tires
    await col("tires").delete_many({"carId": car_id})

    # 4. Delete related inspections 
    await col("inspections").delete_many({"carId": car_id})

    return {"ok": True, "deletedId": car_id}
