import httpx
from app.core.config import settings

async def ocr_tire_code(image_path: str) -> dict:
    """
    ใช้ OCR API ก่อน (http_api)
    อนาคต: เปลี่ยน OCR_PROVIDER เป็น local_model แล้วโหลดโมเดลเองได้
    """
    if settings.OCR_PROVIDER == "http_api":
        if not settings.OCR_HTTP_ENDPOINT:
            return {"text": "", "conf": 0.0}

        async with httpx.AsyncClient(timeout=30) as client:
            with open(image_path, "rb") as f:
                files = {"image": ("image.jpg", f, "image/jpeg")}
                headers = {}
                if settings.OCR_HTTP_API_KEY:
                    headers["Authorization"] = f"Bearer {settings.OCR_HTTP_API_KEY}"
                r = await client.post(settings.OCR_HTTP_ENDPOINT, files=files, headers=headers)
                r.raise_for_status()
                data = r.json()

        return {"text": data.get("text", ""), "conf": float(data.get("conf", 0.0))}

    # stub local_model
    return {"text": "", "conf": 0.0}
