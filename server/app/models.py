from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base
from .roles import Role


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    full_name: Mapped[str] = mapped_column(String(200))
    login: Mapped[str] = mapped_column(String(80), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(200))
    role: Mapped[str] = mapped_column(String(32), default=Role.installer.value)
    confirmed: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class InboxItem(Base):
    """Pending project / price / kit offer for a recipient."""

    __tablename__ = "inbox_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    kind: Mapped[str] = mapped_column(String(32))  # project | prices | kit
    title: Mapped[str] = mapped_column(String(200))
    payload_json: Mapped[str] = mapped_column(Text, default="{}")
    from_login: Mapped[str] = mapped_column(String(80))
    to_login: Mapped[str] = mapped_column(String(80), index=True)
    status: Mapped[str] = mapped_column(String(32), default="pending")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class ArchiveCategory(Base):
    __tablename__ = "archive_categories"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    owner_login: Mapped[str] = mapped_column(String(80), index=True)
    # Stable id from the client (survives reinstall merge).
    client_id: Mapped[str] = mapped_column(String(80), default="", index=True)
    title: Mapped[str] = mapped_column(String(200))
    note: Mapped[str] = mapped_column(Text, default="")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class ArchiveFile(Base):
    """Director archive binary (PDF / Office) — CRM join point later."""

    __tablename__ = "archive_files"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    owner_login: Mapped[str] = mapped_column(String(80), index=True)
    client_id: Mapped[str] = mapped_column(String(80), index=True)
    category_client_id: Mapped[str] = mapped_column(String(80), index=True)
    display_name: Mapped[str] = mapped_column(String(260))
    stored_name: Mapped[str] = mapped_column(String(260))
    content_type: Mapped[str] = mapped_column(String(120), default="application/octet-stream")
    size_bytes: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class AccountSnapshot(Base):
    """Seamless per-user cloud backup (projects, rates, kits, suppliers…)."""

    __tablename__ = "account_snapshots"

    owner_login: Mapped[str] = mapped_column(String(80), primary_key=True)
    payload_json: Mapped[str] = mapped_column(Text, default="{}")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
