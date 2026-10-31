from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import get_session
from .models import User
from .roles import Role, at_least
from .security import decode_token

_bearer = HTTPBearer(auto_error=False)


async def current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: AsyncSession = Depends(get_session),
) -> User:
    if creds is None or not creds.credentials:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Требуется вход")
    try:
        payload = decode_token(creds.credentials)
    except ValueError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Неверный токен") from None
    login = payload.get("sub")
    if not login:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Неверный токен")
    result = await session.execute(select(User).where(User.login == login))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Пользователь не найден")
    return user


def effective_role(user: User) -> Role:
    if not user.confirmed:
        return Role.installer
    return Role(user.role)


def require_role(needed: Role):
    async def _guard(user: User = Depends(current_user)) -> User:
        if not at_least(effective_role(user), needed):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Недостаточно прав")
        return user

    return _guard
