from enum import Enum


class Role(str, Enum):
    installer = "installer"
    foreman = "foreman"
    director = "director"
    super_admin = "super_admin"


ROLE_RANK = {
    Role.installer: 1,
    Role.foreman: 2,
    Role.director: 3,
    Role.super_admin: 4,
}


def at_least(user_role: Role, needed: Role) -> bool:
    return ROLE_RANK[user_role] >= ROLE_RANK[needed]
