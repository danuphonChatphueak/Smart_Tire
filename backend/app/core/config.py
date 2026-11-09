from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    APP_NAME: str = "TireAI"
    ENV: str = "local"

    ADMIN_USERNAME: str = "admin"
    ADMIN_PASSWORD: str = "admin123"

    UPLOAD_DIR: str = "uploads"

    OCR_PROVIDER: str = "http_api"
    OCR_HTTP_ENDPOINT: str = ""
    OCR_HTTP_API_KEY: str = ""

    PUSH_PROVIDER: str = "onesignal"
    ONESIGNAL_APP_ID: str = ""
    ONESIGNAL_API_KEY: str = ""
    GOOGLE_VISION_API_KEY: str = ""
    infer_device: str = "cpu"
    det_model_path: str = "app/models/det_tire_code.pt"
    rec_model_path: str = "app/models/rec_tire_code.pth"
    depth_model_path: str = "app/models/depth_tire.pt"
    mask_model_path: str = "app/models/mask.pt"   # YOLO mask สำหรับวัด gap pixel
    use_internal_recog: bool = True
    crnn_charset: str = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    # Gap-pixel calibration (depth = A * ln(gap_px) + B)
    gap_calib_a: float = 2.85
    gap_calib_b: float = -8.10
    # Strict filtering thresholds
    gap_min_count: int = 10
    gap_min_px: float = 60.0
    gap_max_px: float = 200.0
    gap_max_cv: float = 0.18
    gap_max_mad: float = 10.0
    gap_min_depth_mm: float = 1.6
    gap_max_depth_mm: float = 8.5

    # ─────────────────────────────────────────────
    # ✅ Ultimate Final Profiler v16 — tread settings
    # ─────────────────────────────────────────────
    tread_default_span_mm: float   = 47.901   # ระยะเลเซอร์จริง (mm) ใช้ calibrate px→mm
    tread_scan_density: int        = 450       # จำนวนแนวสแกนแนวตั้ง
    tread_conf_threshold: float    = 0.26      # ความมั่นใจ YOLO ขั้นต่ำ
    tread_mask_threshold: float    = 0.45      # เกณฑ์ binarize mask
    tread_min_gap_px: int          = 4         # ช่องว่างพิกเซลต่ำสุด
    tread_max_gap_px: int          = 350       # ช่องว่างพิกเซลสูงสุด
    tread_min_pattern_span_px: int = 20        # ความกว้าง pattern ขั้นต่ำ
    tread_scan_center_ratio: float = 0.85      # สัดส่วน ROI กลางภาพ
    tread_max_span_ratio: float    = 0.45      # อัตราส่วน span สูงสุดเทียบกับ h
    tread_iqr_multiplier: float    = 1.0       # ตัวคูณ IQR กรอง outlier
    tread_fallback_clip_min: float = 4.5       # clamp ต่ำสุดตอน fallback (mm)
    tread_fallback_clip_max: float = 6.8       # clamp สูงสุดตอน fallback (mm)
    tread_max_valid_grooves: int   = 3         # จำนวนร่องที่ถือว่าถูกต้องสูงสุด

    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",
    )


    

settings = Settings()
