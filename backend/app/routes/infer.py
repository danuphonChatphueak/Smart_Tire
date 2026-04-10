# app/routes/infer.py
from fastapi import APIRouter, UploadFile, File, Form, HTTPException
import cv2
import numpy as np
import inspect

from app.services.models_runtime import get_runtime

router = APIRouter(prefix="/api/infer", tags=["infer"])

@router.post("/scan")
async def infer_scan(
    mode: str = Form("sidewall"),  # 'sidewall' or 'tread'
    image: UploadFile = File(...),
):
    """
    Direct inference without saving to DB.
    Used by apps with local storage that just need the AI result.
    """
    
    # 1. Read image from upload directly to memory (faster for stateless)
    contents = await image.read()
    nparr = np.frombuffer(contents, np.uint8)
    bgr = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    if bgr is None:
        raise HTTPException(status_code=400, detail="Cannot read uploaded image")

    # 2. Get runtime
    rt = get_runtime()

    # 3. Setup result containers
    depth_mm = 0.0
    depth_conf = 0.0
    
    # Sidewall results
    tire_code_res = {"text": "", "conf": 0.0}
    size_code_res = {"text": "", "conf": 0.0}
    rotated_flag = False

    # 4. Branch Logic
    if mode == "sidewall":
        try:
            results = rt.predict_sidewall(bgr)
            tire_code_res = results.get("tire_code", {"text": "", "conf": 0.0})
            size_code_res = results.get("size_code", {"text": "", "conf": 0.0})
            rotated_flag = results.get("rotated", False)
        except Exception as e:
            print(f"[Infer Scan] Sidewall failed: {e}")

    elif mode == "tread":
        try:
            d_val = rt.predict_tread(bgr)
            if d_val is None:
                depth_mm = 0.0 
                depth_conf = 0.0
            else:
                depth_mm = float(d_val)
                depth_conf = 0.8
        except Exception as e:
            print(f"[Infer Scan] Tread failed: {e}")
            depth_conf = 0.0

    # 5. Return JSON (Stateless)
    return {
        "mode": mode,
        "rotated": rotated_flag,
        "results": {
             "tire_code": tire_code_res,
             "size_code": size_code_res
        },
        "depthMm": {"value": depth_mm, "conf": float(depth_conf)},
    }
