from fastapi import FastAPI

from app.api.activation import router as activation_router
from app.api.admin_keys import router as admin_keys_router
from app.api.health import router as health_router
from app.api.validation import router as validation_router
from app.api.vpn_config import router as vpn_config_router
from app.api.vpn_session import router as vpn_session_router
from app.core.config import settings


app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    debug=settings.debug,
)

app.include_router(
    activation_router,
    prefix="/api/v1",
    tags=["Activation"],
)

app.include_router(
    admin_keys_router,
    prefix="/api/v1",
)

app.include_router(
    validation_router,
    prefix="/api/v1",
)

app.include_router(
    vpn_config_router,
    prefix="/api/v1",
)

app.include_router(
    vpn_session_router,
    prefix="/api/v1",
)

app.include_router(
    health_router,
    prefix="/api/v1",
)
