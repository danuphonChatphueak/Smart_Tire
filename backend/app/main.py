from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pathlib import Path
from app.core.config import settings

from app.routes.infer import router as infer_router

app = FastAPI(title=settings.APP_NAME)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # โปรเจกต์จริงควรจำกัด
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Static files — ให้ admin web ดูรูปที่ user อัปโหลดได้
uploads_dir = Path(settings.UPLOAD_DIR)
uploads_dir.mkdir(exist_ok=True)
app.mount("/uploads", StaticFiles(directory=str(uploads_dir)), name="uploads")

app.include_router(infer_router)