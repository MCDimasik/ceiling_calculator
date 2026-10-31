from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..deps import current_user, effective_role, require_role
from ..models import User
from ..roles import Role
from ..schemas import (
    ConfirmRoleIn,
    LoginIn,
    RegisterIn,
    TokenOut,
    UserOut,
)
from ..security import create_access_token, hash_password, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])


def _user_out(user: User) -> UserOut:
    requested = Role(user.role)
    return UserOut(
        full_name=user.full_name,
        login=user.login,
        requested_role=requested,
        confirmed=user.confirmed,
        effective_role=effective_role(user),
    )


@router.post("/register", response_model=TokenOut)
async def register(body: RegisterIn, session: AsyncSession = Depends(get_session)):
    login = body.login.strip().lower()
    if body.requested_role == Role.super_admin:
        raise HTTPException(400, "Супер-админ пока недоступен")
    existing = await session.execute(select(User).where(User.login == login))
    if existing.scalar_one_or_none():
        raise HTTPException(409, "Логин занят")

    directors = await session.execute(
        select(User).where(
            User.confirmed.is_(True),
            User.role.in_([Role.director.value, Role.super_admin.value]),
        )
    )
    has_director = directors.scalars().first() is not None
    auto_confirm = body.requested_role == Role.installer or (
        body.requested_role == Role.director and not has_director
    )

    user = User(
        full_name=body.full_name.strip(),
        login=login,
        password_hash=hash_password(body.password),
        role=body.requested_role.value,
        confirmed=auto_confirm,
    )
    session.add(user)
    await session.commit()
    token = create_access_token(
        sub=user.login, role=user.role, confirmed=user.confirmed
    )
    return TokenOut(access_token=token)


@router.post("/login", response_model=TokenOut)
async def login(body: LoginIn, session: AsyncSession = Depends(get_session)):
    login = body.login.strip().lower()
    result = await session.execute(select(User).where(User.login == login))
    user = result.scalar_one_or_none()
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Неверный логин или пароль")
    token = create_access_token(
        sub=user.login, role=user.role, confirmed=user.confirmed
    )
    return TokenOut(access_token=token)


@router.get("/me", response_model=UserOut)
async def me(user: User = Depends(current_user)):
    return _user_out(user)


@router.get("/directory", response_model=list[UserOut])
async def directory(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
):
    """Confirmed users for offer recipient picker (names + logins)."""
    result = await session.execute(
        select(User)
        .where(User.confirmed.is_(True))
        .order_by(User.full_name.asc())
    )
    return [
        _user_out(u)
        for u in result.scalars().all()
        if u.login != user.login
    ]


@router.get("/pending", response_model=list[UserOut])
async def pending_users(
    _: User = Depends(require_role(Role.director)),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(select(User).where(User.confirmed.is_(False)))
    return [_user_out(u) for u in result.scalars().all()]


@router.post("/confirm", response_model=UserOut)
async def confirm_role(
    body: ConfirmRoleIn,
    _: User = Depends(require_role(Role.director)),
    session: AsyncSession = Depends(get_session),
):
    target_login = body.target_login.strip().lower()
    result = await session.execute(select(User).where(User.login == target_login))
    target = result.scalar_one_or_none()
    if target is None:
        raise HTTPException(404, "Профиль не найден")
    target.confirmed = True
    await session.commit()
    await session.refresh(target)
    return _user_out(target)
