import logging
from typing import Any

from fastapi import HTTPException

from app import pb

log = logging.getLogger("orgs")

ROLES = {"owner", "admin", "member"}


def _rel(value: Any) -> str | None:
    if isinstance(value, list):
        return value[0] if value else None
    return value


async def get_membership(user_id: str, org_id: str) -> dict[str, Any] | None:
    items = await pb.list_records(
        "org_members", filter=f'user_id = "{user_id}" && org_id = "{org_id}"'
    )
    return items[0] if items else None


async def get_org_for_user(user_id: str) -> tuple[dict[str, Any], str] | None:
    items = await pb.list_records("org_members", filter=f'user_id = "{user_id}"')
    if not items:
        return None
    membership = items[0]
    org_id = _rel(membership.get("org_id"))
    if not org_id:
        return None
    org = await pb.get_record("organizations", org_id)
    if org is None:
        return None
    return org, membership.get("role") or "member"


def _public_member(membership: dict[str, Any]) -> dict[str, Any]:
    expanded = (membership.get("expand") or {}).get("user_id") or {}
    return {
        "id": membership["id"],
        "user_id": _rel(membership.get("user_id")) or "",
        "email": expanded.get("email") or "",
        "name": expanded.get("name") or "",
        "role": membership.get("role") or "member",
    }


async def public_org(org: dict[str, Any], role: str, user_id: str) -> dict[str, Any]:
    members = await list_members(org["id"])
    return {
        "id": org["id"],
        "name": org.get("name"),
        "brand_guidelines": {
            "brand_name": org.get("brand_name"),
            "tagline": org.get("tagline"),
            "tone_of_voice": org.get("tone_of_voice"),
            "colors": org.get("colors"),
            "typography": org.get("typography"),
            "visual_style": org.get("visual_style"),
            "do_list": org.get("do_list"),
            "dont_list": org.get("dont_list"),
            "target_audience": org.get("target_audience"),
        },
        "my_role": role,
        "members": members,
    }


async def list_members(org_id: str) -> list[dict[str, Any]]:
    items = await pb.list_records(
        "org_members", filter=f'org_id = "{org_id}"', expand="user_id"
    )
    members = []
    for item in items:
        user_id = _rel(item.get("user_id"))
        if not user_id:
            continue
        members.append(_public_member(item))
    return members


def _branding_data(brand: dict[str, Any] | None) -> dict[str, Any]:
    data: dict[str, Any] = {}
    if not brand:
        return data
    for key, pb_key in (
        ("brand_name", "brand_name"),
        ("tagline", "tagline"),
        ("tone_of_voice", "tone_of_voice"),
        ("typography", "typography"),
        ("visual_style", "visual_style"),
        ("target_audience", "target_audience"),
    ):
        if brand.get(key) is not None:
            data[pb_key] = brand[key]
    for key, pb_key in (("colors", "colors"), ("do_list", "do_list"), ("dont_list", "dont_list")):
        if brand.get(key) is not None:
            data[pb_key] = brand[key]
    return data


async def create_org(org_name: str, brand: dict[str, Any] | None, owner: dict[str, Any]) -> dict[str, Any]:
    org = await pb.create_record(
        "organizations", {"name": org_name, **_branding_data(brand)}
    )
    await pb.create_record(
        "org_members",
        {"org_id": org["id"], "user_id": owner["id"], "role": "owner"},
    )
    log.info("org %s created with owner %s", org["id"], owner["id"])
    return org


async def update_org(org_id: str, name: str | None, brand: dict[str, Any] | None) -> dict[str, Any]:
    data: dict[str, Any] = {}
    if name is not None:
        data["name"] = name
    data.update(_branding_data(brand))
    return await pb.update_record("organizations", org_id, data)


async def add_member(org_id: str, email: str, role: str) -> dict[str, Any]:
    if role not in ROLES:
        raise HTTPException(status_code=422, detail=f"Role must be one of {sorted(ROLES)}")
    user = await pb.find_user_by_email(email.lower().strip())
    if user is None:
        raise HTTPException(status_code=404, detail="No account found with that email")
    existing = await get_membership(user["id"], org_id)
    if existing:
        raise HTTPException(status_code=409, detail="User is already a member")
    member = await pb.create_record(
        "org_members",
        {"org_id": org_id, "user_id": user["id"], "role": role},
    )
    return {**_public_member(member), "email": user.get("email"), "name": user.get("name") or ""}


async def set_member_role(org_id: str, member_id: str, role: str) -> dict[str, Any]:
    if role not in ROLES:
        raise HTTPException(status_code=422, detail=f"Role must be one of {sorted(ROLES)}")
    member = await pb.get_record("org_members", member_id)
    if member is None or _rel(member.get("org_id")) != org_id:
        raise HTTPException(status_code=404, detail="Member not found")
    if member.get("role") == "owner" and role != "owner":
        owners = await pb.list_records(
            "org_members", filter=f'org_id = "{org_id}" && role = "owner"'
        )
        if len(owners) <= 1:
            raise HTTPException(status_code=409, detail="An organization must keep at least one owner")
    updated = await pb.update_record("org_members", member_id, {"role": role})
    return _public_member(updated)


async def remove_member(org_id: str, member_id: str, actor_id: str) -> None:
    member = await pb.get_record("org_members", member_id)
    if member is None or _rel(member.get("org_id")) != org_id:
        raise HTTPException(status_code=404, detail="Member not found")
    member_user_id = _rel(member.get("user_id"))
    if member_user_id == actor_id and member.get("role") == "owner":
        owners = await pb.list_records(
            "org_members", filter=f'org_id = "{org_id}" && role = "owner"'
        )
        if len(owners) <= 1:
            raise HTTPException(status_code=409, detail="An organization must keep at least one owner")
    await pb.delete_record("org_members", member_id)


def require_owner_or_admin(role: str) -> None:
    if role not in {"owner", "admin"}:
        raise HTTPException(status_code=403, detail="Only owners and admins can do that")


async def require_org_access(user: dict[str, Any]) -> tuple[dict[str, Any], str]:
    found = await get_org_for_user(user["id"])
    if found is None:
        raise HTTPException(status_code=404, detail="No organization for this user")
    return found