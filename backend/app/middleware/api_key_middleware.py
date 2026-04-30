"""API key middleware — ensures only authorized clients (the mobile app) can
call the backend. The key is passed via the X-API-Key header and checked
against the APP_API_KEY env var.

Excluded paths (no key required):
- /docs, /openapi.json (Swagger UI)
- /subscription/webhook/* (RevenueCat sends its own auth header)
"""

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import settings

# Paths that don't require the API key
_EXCLUDED_PREFIXES = (
    "/docs",
    "/openapi.json",
    "/redoc",
    "/subscription/webhook",
)


class APIKeyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # Skip if no key is configured (development mode)
        if not settings.APP_API_KEY:
            return await call_next(request)

        # Skip excluded paths
        path = request.url.path
        if any(path.startswith(prefix) for prefix in _EXCLUDED_PREFIXES):
            return await call_next(request)

        # Check the header
        api_key = request.headers.get("X-API-Key")
        if api_key != settings.APP_API_KEY:
            return JSONResponse(
                status_code=401,
                content={"detail": "Invalid or missing API key."},
            )

        return await call_next(request)
