from app.db.session import engine
from app.db.base import Base

# Register all models on Base.metadata
from app.models.access_key import AccessKey  # noqa: F401
from app.models.device import Device  # noqa: F401
from app.models.vpn_session import VpnSession  # noqa: F401


async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


if __name__ == "__main__":
    import asyncio

    asyncio.run(init_db())
