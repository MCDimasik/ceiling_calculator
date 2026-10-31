from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user
from ..models import AccountSnapshot, User
from ..schemas import AccountSnapshotIn, AccountSnapshotOut

router = APIRouter(prefix="/account", tags=["account"])


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


@router.get("/snapshot", response_model=AccountSnapshotOut | None)
async def get_snapshot(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
):
    """Seamless restore: projects / rates / kits / suppliers JSON for this login."""
    result = await session.execute(
        select(AccountSnapshot).where(AccountSnapshot.owner_login == user.login)
    )
    row = result.scalar_one_or_none()
    if row is None:
        return None
    return AccountSnapshotOut(
        owner_login=row.owner_login,
        updated_at=row.updated_at,
        payload_json=row.payload_json,
    )


@router.put("/snapshot", response_model=AccountSnapshotOut)
async def put_snapshot(
    body: AccountSnapshotIn,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
):
    """Upsert account backup. Client should LWW-merge before push."""
    if not body.payload_json or not body.payload_json.strip():
        raise HTTPException(400, "Пустой снимок")
    if len(body.payload_json) > 80 * 1024 * 1024:
        raise HTTPException(413, "Снимок слишком большой")

    result = await session.execute(
        select(AccountSnapshot).where(AccountSnapshot.owner_login == user.login)
    )
    row = result.scalar_one_or_none()
    stamp = body.updated_at or _utc_now()
    if row is None:
        row = AccountSnapshot(
            owner_login=user.login,
            payload_json=body.payload_json,
            updated_at=stamp,
        )
        session.add(row)
    else:
        # Client is expected to LWW-merge before PUT; store the merged snapshot.
        row.payload_json = body.payload_json
        row.updated_at = stamp
    await session.commit()
    await session.refresh(row)
    return AccountSnapshotOut(
        owner_login=row.owner_login,
        updated_at=row.updated_at,
        payload_json=row.payload_json,
    )
