from app.db.session import engine
from app.db.base import Base

# Импортируем модели, чтобы SQLAlchemy "узнал" о них
from app.models.access_key import AccessKey


async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


if __name__ == "__main__":
    import asyncio

    asyncio.run(init_db())