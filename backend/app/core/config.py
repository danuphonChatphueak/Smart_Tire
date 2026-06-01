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

    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",
    )


    

settings = Settings()
