from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

from .roles import Role


class RegisterIn(BaseModel):
    full_name: str = Field(min_length=1, max_length=200)
    login: str = Field(min_length=2, max_length=80)
    password: str = Field(min_length=4, max_length=128)
    requested_role: Role = Role.foreman


class LoginIn(BaseModel):
    login: str
    password: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    full_name: str
    login: str
    requested_role: Role
    confirmed: bool
    effective_role: Role


class ConfirmRoleIn(BaseModel):
    target_login: str


class InboxItemOut(BaseModel):
    id: int
    kind: Literal["project", "prices", "kit"]
    title: str
    from_login: str
    status: str
    created_at: datetime
    payload_json: str = "{}"


class InboxCreateIn(BaseModel):
    kind: Literal["project", "prices", "kit"]
    title: str
    to_login: str
    payload_json: str = "{}"


class InboxDecideIn(BaseModel):
    accept: bool
    target_project_id: str | None = None


class ArchiveCategoryIn(BaseModel):
    title: str
    note: str = ""
    client_id: str = ""
    updated_at: datetime | None = None


class ArchiveCategoryOut(BaseModel):
    id: int
    title: str
    note: str
    client_id: str = ""
    updated_at: datetime | None = None


class ArchiveFileOut(BaseModel):
    id: int
    client_id: str
    category_client_id: str
    display_name: str
    content_type: str
    size_bytes: int
    updated_at: datetime


class AccountSnapshotOut(BaseModel):
    owner_login: str
    updated_at: datetime
    payload_json: str


class AccountSnapshotIn(BaseModel):
    payload_json: str
    updated_at: datetime | None = None


class HealthOut(BaseModel):
    ok: bool
    service: str = "ceiling-sync"
    version: str = "0.2.0"
