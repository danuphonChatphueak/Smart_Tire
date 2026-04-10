from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from bson import ObjectId
from typing import Any, Optional
from app.core.deps import require_admin
from app.core.db import col

router = APIRouter(prefix="/api/admin/db", tags=["admin-db"])

ALLOWED = {"users", "cars", "tires", "inspections", "formula_configs", "devices"}

def _oid(s: str) -> ObjectId:
    try:
        return ObjectId(s)
    except Exception:
        raise HTTPException(400, "Invalid id")

def _sanitize(doc: dict) -> dict:
    if not doc:
        return doc
    doc["_id"] = str(doc["_id"])
    return doc

@router.get("/collections")
async def list_collections(token: str):
    require_admin(token)
    return sorted(list(ALLOWED))

@router.get("/{collection}")
async def list_docs(
    collection: str,
    token: str,
    page: int = 1,
    limit: int = 20,
    q: Optional[str] = None,      # search แบบง่าย
    field: Optional[str] = None,  # search field (เช่น plateNo)
):
    require_admin(token)
    if collection not in ALLOWED:
        raise HTTPException(400, "collection not allowed")

    page = max(1, page)
    limit = min(max(1, limit), 100)
    skip = (page - 1) * limit

    query: dict[str, Any] = {}
    if q and field:
        # search แบบ contains (regex)
        query[field] = {"$regex": q, "$options": "i"}

    cursor = col(collection).find(query).skip(skip).limit(limit).sort([("_id", -1)])
    items = await cursor.to_list(limit)
    items = [_sanitize(x) for x in items]
    total = await col(collection).count_documents(query)

    return {
        "page": page,
        "limit": limit,
        "total": total,
        "items": items,
    }

@router.get("/{collection}/{doc_id}")
async def get_doc(collection: str, doc_id: str, token: str):
    require_admin(token)
    if collection not in ALLOWED:
        raise HTTPException(400, "collection not allowed")

    doc = await col(collection).find_one({"_id": _oid(doc_id)})
    if not doc:
        raise HTTPException(404, "not found")
    return _sanitize(doc)

class UpdateReq(BaseModel):
    # ส่งเป็น JSON object ที่ต้องการแก้ (partial update)
    patch: dict

@router.patch("/{collection}/{doc_id}")
async def patch_doc(collection: str, doc_id: str, token: str, body: UpdateReq):
    require_admin(token)
    if collection not in ALLOWED:
        raise HTTPException(400, "collection not allowed")

    # กันแก้ _id
    if "_id" in body.patch:
        body.patch.pop("_id")

    r = await col(collection).update_one({"_id": _oid(doc_id)}, {"$set": body.patch})
    if r.matched_count == 0:
        raise HTTPException(404, "not found")
    doc = await col(collection).find_one({"_id": _oid(doc_id)})
    return _sanitize(doc)

class CreateReq(BaseModel):
    doc: dict

@router.post("/{collection}")
async def create_doc(collection: str, token: str, body: CreateReq):
    require_admin(token)
    if collection not in ALLOWED:
        raise HTTPException(400, "collection not allowed")

    # กันการส่ง _id เอง
    if "_id" in body.doc:
        body.doc.pop("_id")

    r = await col(collection).insert_one(body.doc)
    doc = await col(collection).find_one({"_id": r.inserted_id})
    return _sanitize(doc)

@router.delete("/{collection}/{doc_id}")
async def delete_doc(collection: str, doc_id: str, token: str):
    require_admin(token)
    if collection not in ALLOWED:
        raise HTTPException(400, "collection not allowed")

    r = await col(collection).delete_one({"_id": _oid(doc_id)})
    if r.deleted_count == 0:
        raise HTTPException(404, "not found")
    return {"ok": True, "deletedId": doc_id}
