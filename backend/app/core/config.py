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
    use_internal_recog: bool = True
    crnn_charset: str = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",
    )


    

settings = Settings()
