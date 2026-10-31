import uuid
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import require_role
from ..models import ArchiveCategory, ArchiveFile, User
from ..roles import Role
from ..schemas import ArchiveCategoryIn, ArchiveCategoryOut, ArchiveFileOut
from ..settings import archive_files_dir

router = APIRouter(prefix="/archive", tags=["archive"])

_ALLOWED_EXT = {
    ".pdf",
    ".doc",
    ".docx",
    ".xls",
    ".xlsx",
    ".odt",
    ".ods",
    ".rtf",
    ".txt",
    ".csv",
}


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _safe_ext(name: str) -> str:
    ext = Path(name).suffix.lower()
    return ext if ext in _ALLOWED_EXT else ".bin"


@router.get("", response_model=list[ArchiveCategoryOut])
async def list_categories(
    user: User = Depends(require_role(Role.director)),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(ArchiveCategory)
        .where(ArchiveCategory.owner_login == user.login)
        .order_by(ArchiveCategory.id)
    )
    return [
        ArchiveCategoryOut(
            id=c.id,
            title=c.title,
            note=c.note,
            client_id=c.client_id or "",
            updated_at=c.updated_at,
        )
        for c in result.scalars().all()
    ]


@router.post("", response_model=ArchiveCategoryOut)
async def create_category(
    body: ArchiveCategoryIn,
    user: User = Depends(require_role(Role.director)),
    session: AsyncSession = Depends(get_session),
):
    client_id = (body.client_id or "").strip() or str(uuid.uuid4())
    existing = await session.execute(
        select(ArchiveCategory).where(
            ArchiveCategory.owner_login == user.login,
            ArchiveCategory.client_id == client_id,
        )
    )
    cat = existing.scalar_one_or_none()
    stamp = body.updated_at or _utc_now()
    if cat is None:
        cat = ArchiveCategory(
            owner_login=user.login,
            client_id=client_id,
            title=body.title.strip(),
            note=body.note.strip(),
            updated_at=stamp,
        )
        session.add(cat)
    else:
        cat.title = body.title.strip()
        cat.note = body.note.strip()
        cat.updated_at = stamp
    await session.commit()
    await session.refresh(cat)
    return ArchiveCategoryOut(
        id=cat.id,
        title=cat.title,
        note=cat.note,
        client_id=cat.client_id,
        updated_at=cat.updated_at,
    )


@router.patch("/{cat_id}", response_model=ArchiveCategoryOut)
async def update_category(
    cat_id: int,
    body: ArchiveCategoryIn,
    user: User = Depends(require_role(Role.director)),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(ArchiveCategory).where(ArchiveCategory.id == cat_id)
    )
    cat = result.scalar_one_or_none()
    if cat is None or cat.owner_login != user.login:
        raise HTTPException(404, "Категория не найдена")
    cat.title = body.title.strip()
    cat.note = body.note.strip()
    if body.client_id.strip():
        cat.client_id = body.client_id.strip()
    cat.updated_at = body.updated_at or _utc_now()
    await session.commit()
    await session.refresh(cat)
    return ArchiveCategoryOut(
        id=cat.id,
        title=cat.title,
        note=cat.note,
        client_id=cat.client_id,
        updated_at=cat.updated_at,
    )


@router.delete("/{cat_id}")
async def delete_category(
    cat_id: int,
    user: User = Depends(require_role(Role.director)),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(ArchiveCategory).where(ArchiveCategory.id == cat_id)
    )
    cat = result.scalar_one_or_none()
    if cat is None or cat.owner_login != user.login:
        raise HTTPException(404, "Категория не найдена")
    await session.delete(cat)
    await session.commit()
    return {"ok": True}


@router.get("/files", response_model=list[ArchiveFileOut])
async def list_files(
    user: User = Depends(require_role(Role.director)),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(ArchiveFile)
        .where(ArchiveFile.owner_login == user.login)
        .order_by(ArchiveFile.id)
    )
    return [
        ArchiveFileOut(
            id=f.id,
            client_id=f.client_id,
            category_client_id=f.category_client_id,
            display_name=f.display_name,
            content_type=f.content_type,
            size_bytes=f.size_bytes,
            updated_at=f.updated_at,
        )
        for f in result.scalars().all()
    ]


@router.post("/files", response_model=ArchiveFileOut)
async def upload_file(
    category_client_id: str = Form(...),
    client_id: str = Form(""),
    display_name: str = Form(""),
    file: UploadFile = File(...),
    user: User = Depends(require_role(Role.director)),
    session: AsyncSession = Depends(get_session),
):
    cid = (client_id or "").strip() or str(uuid.uuid4())
    cat_id = category_client_id.strip()
    if not cat_id:
        raise HTTPException(400, "category_client_id обязателен")
    raw_name = display_name.strip() or (file.filename or "file")
    ext = _safe_ext(raw_name if Path(raw_name).suffix else (file.filename or ""))
    stored = f"{cid}{ext}"
    dest = archive_files_dir(user.login) / stored
    data = await file.read()
    if len(data) > 40 * 1024 * 1024:
        raise HTTPException(413, "Файл больше 40 МБ")
    dest.write_bytes(data)

    result = await session.execute(
        select(ArchiveFile).where(
            ArchiveFile.owner_login == user.login,
            ArchiveFile.client_id == cid,
        )
    )
    row = result.scalar_one_or_none()
    stamp = _utc_now()
    ctype = file.content_type or "application/octet-stream"
    if row is None:
        row = ArchiveFile(
            owner_login=user.login,
            client_id=cid,
            category_client_id=cat_id,
            display_name=raw_name,
            stored_name=stored,
            content_type=ctype,
            size_bytes=len(data),
            updated_at=stamp,
        )
        session.add(row)
    else:
        old = archive_files_dir(user.login) / row.stored_name
        if old.exists() and old != dest:
            try:
                old.unlink()
            except OSError:
                pass
        row.category_client_id = cat_id
        row.display_name = raw_name
        row.stored_name = stored
        row.content_type = ctype
        row.size_bytes = len(data)
        row.updated_at = stamp
    await session.commit()
    await session.refresh(row)
    return ArchiveFileOut(
        id=row.id,
        client_id=row.client_id,
        category_client_id=row.category_client_id,
        display_name=row.display_name,
        content_type=row.content_type,
        size_bytes=row.size_bytes,
        updated_at=row.updated_at,
    )


@router.get("/files/{file_id}/download")
async def download_file(
    file_id: int,
    user: User = Depends(require_role(Role.director)),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(ArchiveFile).where(ArchiveFile.id == file_id)
    )
    row = result.scalar_one_or_none()
    if row is None or row.owner_login != user.login:
        raise HTTPException(404, "Файл не найден")
    path = archive_files_dir(user.login) / row.stored_name
    if not path.exists():
        raise HTTPException(404, "Содержимое файла отсутствует на сервере")
    return FileResponse(
        path,
        media_type=row.content_type,
        filename=row.display_name,
    )


@router.delete("/files/{file_id}")
async def delete_file(
    file_id: int,
    user: User = Depends(require_role(Role.director)),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(ArchiveFile).where(ArchiveFile.id == file_id)
    )
    row = result.scalar_one_or_none()
    if row is None or row.owner_login != user.login:
        raise HTTPException(404, "Файл не найден")
    path = archive_files_dir(user.login) / row.stored_name
    if path.exists():
        try:
            path.unlink()
        except OSError:
            pass
    await session.delete(row)
    await session.commit()
    return {"ok": True}
