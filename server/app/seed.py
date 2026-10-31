from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .models import User
from .roles import Role
from .security import hash_password

# Always ensure these logins exist (idempotent upsert by login).
_DEMO = [
    ("Супер-админ", "admin", Role.super_admin, True),
    ("Демо Монтажник", "monter", Role.installer, True),
    ("Демо Бригадир", "brigadir", Role.foreman, True),
    ("Демо Директор", "director", Role.director, True),
    # Unconfirmed foreman — for director «Подтвердить роль» E2E.
    ("Новичок Тест", "novichok", Role.foreman, False),
]

_DEMO_PASSWORD = "demo1234"


async def seed_demo_users(session: AsyncSession) -> None:
    for full_name, login, role, confirmed in _DEMO:
        result = await session.execute(select(User).where(User.login == login))
        existing = result.scalar_one_or_none()
        if existing is None:
            session.add(
                User(
                    full_name=full_name,
                    login=login,
                    password_hash=hash_password(_DEMO_PASSWORD),
                    role=role.value,
                    confirmed=confirmed,
                )
            )
            continue
        # Keep password; promote role/flags for known demo accounts.
        existing.full_name = full_name
        existing.role = role.value
        existing.confirmed = confirmed
        if login == "admin":
            existing.password_hash = hash_password(_DEMO_PASSWORD)
    await session.commit()
