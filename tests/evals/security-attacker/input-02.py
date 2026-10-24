# Golden set: Clean code — no vulnerabilities
# Agent must NOT find any security issues here

import hashlib
import secrets

def _kdf(password: str, salt: str) -> str:
    return hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=2**14, r=8, p=1).hex()

def hash_password(password: str) -> tuple[str, str]:
    """Hash password with random salt using scrypt (memory-hard KDF)."""
    salt = secrets.token_hex(16)
    return salt, _kdf(password, salt)

def verify_password(password: str, salt: str, expected_hash: str) -> bool:
    """Verify password against stored hash."""
    return secrets.compare_digest(_kdf(password, salt), expected_hash)
