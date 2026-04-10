import os, uuid
from fastapi import UploadFile
from app.core.config import settings

os.makedirs(settings.UPLOAD_DIR, exist_ok=True)

async def save_upload(file: UploadFile) -> str:
    ext = os.path.splitext(file.filename or "")[1].lower() or ".jpg"
    name = f"{uuid.uuid4().hex}{ext}"
    path = os.path.join(settings.UPLOAD_DIR, name)

    content = await file.read()
    with open(path, "wb") as f:
        f.write(content)
    return path
