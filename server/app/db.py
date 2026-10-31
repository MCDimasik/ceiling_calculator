from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from .settings import settings


class Base(DeclarativeBase):
    pass


_engine = create_async_engine(f"sqlite+aiosqlite:///{settings.db}", echo=False)
SessionLocal = async_sessionmaker(_engine, expire_on_commit=False)


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    async with SessionLocal() as session:
        yield session


async def init_db() -> None:
    from . import models  # noqa: F401

    async with _engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await conn.run_sync(_sqlite_migrate)


def _sqlite_migrate(sync_conn) -> None:
    """Add columns introduced after first local installs (SQLite)."""
    rows = sync_conn.exec_driver_sql("PRAGMA table_info(archive_categories)").fetchall()
    cols = {r[1] for r in rows}
    if cols and "client_id" not in cols:
        sync_conn.exec_driver_sql(
            "ALTER TABLE archive_categories ADD COLUMN client_id VARCHAR(80) DEFAULT ''"
        )
    if cols and "updated_at" not in cols:
        sync_conn.exec_driver_sql(
            "ALTER TABLE archive_categories ADD COLUMN updated_at DATETIME"
        )
