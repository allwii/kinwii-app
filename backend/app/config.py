from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DATABASE_URL: str
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 10080  # 7 days
    OPENAI_API_KEY: str = ""
    OPENAI_MODEL: str = "gpt-5.2"
    ENVIRONMENT: str = "development"
    REVENUECAT_WEBHOOK_SECRET: str = ""
    RESEND_API_KEY: str = ""
    GOOGLE_CLIENT_ID_IOS: str = ""
    GOOGLE_CLIENT_ID_ANDROID: str = ""
    GOOGLE_CLIENT_ID_WEB: str = ""
    APP_API_KEY: str = ""  # Shared secret for mobile app authentication

    # Local-only paywall bypass — when true (and ENVIRONMENT != "production"),
    # all users are treated as Pro. Safe-by-default off. Set in .env for
    # simulator testing.
    BYPASS_PAYWALL: bool = False

    model_config = {"env_file": ".env"}


settings = Settings()
