"""Authentication extension point. JWT is intentionally not enabled in phase one."""


def build_bearer_token_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}
