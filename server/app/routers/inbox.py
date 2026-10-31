from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user, effective_role
from ..models import InboxItem, User
from ..roles import Role, at_least
from ..schemas import InboxCreateIn, InboxDecideIn, InboxItemOut

router = APIRouter(prefix="/inbox", tags=["inbox"])


def _out(item: InboxItem) -> InboxItemOut:
    return InboxItemOut(
        id=item.id,
        kind=item.kind,  # type: ignore[arg-type]
        title=item.title,
        from_login=item.from_login,
        status=item.status,
        created_at=item.created_at,
        payload_json=item.payload_json or "{}",
    )


@router.get("", response_model=list[InboxItemOut])
async def list_inbox(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
):
    # Installer may receive project offers; prices/kits need foreman+.
    result = await session.execute(
        select(InboxItem)
        .where(
            InboxItem.to_login == user.login,
            InboxItem.status == "pending",
        )
        .order_by(InboxItem.id.desc())
    )
    items = list(result.scalars().all())
    role = effective_role(user)
    if not at_least(role, Role.foreman):
        items = [i for i in items if i.kind == "project"]
    return [_out(i) for i in items]


@router.get("/counts")
async def inbox_counts(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(InboxItem).where(
            InboxItem.to_login == user.login,
            InboxItem.status == "pending",
        )
    )
    items = list(result.scalars().all())
    role = effective_role(user)
    if not at_least(role, Role.foreman):
        items = [i for i in items if i.kind == "project"]
    return {
        "project": sum(1 for i in items if i.kind == "project"),
        "prices": sum(1 for i in items if i.kind == "prices"),
        "kit": sum(1 for i in items if i.kind == "kit"),
        "total": len(items),
    }


@router.post("", response_model=InboxItemOut)
async def create_offer(
    body: InboxCreateIn,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
):
    # Any signed-in role may send offers (incl. installer → projects).
    _ = effective_role(user)
    item = InboxItem(
        kind=body.kind,
        title=body.title.strip(),
        payload_json=body.payload_json,
        from_login=user.login,
        to_login=body.to_login.strip().lower(),
        status="pending",
    )
    session.add(item)
    await session.commit()
    await session.refresh(item)
    return _out(item)


@router.post("/{item_id}/decide", response_model=InboxItemOut)
async def decide(
    item_id: int,
    body: InboxDecideIn,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(select(InboxItem).where(InboxItem.id == item_id))
    item = result.scalar_one_or_none()
    if item is None or item.to_login != user.login:
        raise HTTPException(404, "Нет такого входящего")
    if item.status != "pending":
        raise HTTPException(409, "Уже обработано")
    item.status = "accepted" if body.accept else "rejected"
    # target_project_id reserved for Flutter apply step
    _ = body.target_project_id
    await session.commit()
    await session.refresh(item)
    return _out(item)
