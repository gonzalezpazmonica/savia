#!/usr/bin/env python3
"""
Savia Bridge — HTTPS server bridging Savia Mobile and a selected CLI adapter.

Module Purpose:
    This module implements a lightweight Python HTTPS server that acts as a bridge
    between the Savia Mobile Android app and a CLI-managed provider. It provides:

    1. HTTPS endpoints for chat, health checks, and session management
    2. Server-Sent Events (SSE) streaming of Claude responses
    3. User profile injection into Claude prompts
    4. APK distribution for Savia Mobile
    5. TLS certificate management (self-signed, auto-generated)

Architecture:
    Savia Mobile App (Android)
            ↓ HTTPS/SSE streaming
        [VPN/Local Network]
            ↓
    Savia Bridge (Python HTTPS server, this module)
            ↓ stdio pipes
        Selected CLI Adapter
            ↓
    Provider selected by the CLI adapter

Endpoints:
    POST   /chat              Send message, receive SSE stream response
    GET    /health            Health check (no auth required)
    GET    /sessions          List active sessions
    DELETE /sessions          Clear session history
    GET    /install           HTML page for APK download (no auth)
    GET    /download/apk      Download APK binary (no auth)
    GET    /update/check      Check available APK version and metadata (no auth)
    GET    /update/download   Download APK for auto-update (no auth)
    GET    /profile           User profile (name, email, company, role) (no auth)
    PUT    /profile           Save user preferences from mobile app (requires Bearer auth)
    GET    /git-config        Git global config (name, email, PAT status) (no auth)
    PUT    /git-config        Update git global config (requires Bearer auth)
    GET    /team              Team members from .claude/profiles/users/ (no auth)
    PUT    /team              Add/update/remove team members (requires Bearer auth)
    GET    /company           Company configuration sections (no auth)
    PUT    /company           Update company profile sections (requires Bearer auth)
    GET    /connectors        External service connectors (no auth)
    GET    /files?path=X      List directory contents or file metadata (requires Bearer auth)
    GET    /files/content?path=X  Read file content (text only, max 500KB) (requires Bearer auth)
    GET    /openapi.json      OpenAPI 3.0 specification in YAML (no auth)

Configuration Files (created automatically):
    ~/.savia/bridge/bridge.log              General server logs
    ~/.savia/bridge/chat.log                Detailed request/response logs
    ~/.savia/bridge/auth_token              Bearer token for authentication
    ~/.savia/bridge/cert.pem                Self-signed TLS certificate
    ~/.savia/bridge/key.pem                 TLS private key
    ~/.savia/bridge/cert_fingerprint.txt    SHA-256 fingerprint
    ~/.savia/bridge/profile.json            User profile (name, role, email)
    ~/.savia/bridge/sessions/               Claude CLI session directory
    ~/.savia/bridge/apk/                    APK files for distribution

Usage:
    python3 savia-bridge.py [--port 8922] [--cli-adapter claude|codex|opencode]

Design Principles:
    - Zero external dependencies (stdlib only)
    - Auto-generates TLS certificates and auth tokens on first run
    - Per-session locking to prevent concurrent CLI calls
    - Streaming responses via SSE for low latency
    - Detailed logging for debugging
"""

import argparse
import hashlib
import http.server
import json
import os
import re
import secrets
import shutil
import ssl
import subprocess
import sys
import threading
import time
import traceback
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse, parse_qs

from bridge_cli_adapters import (
    AdapterContractError,
    BridgeRequest,
    adapter_by_id,
)

# --- Configuration ---

DEFAULT_PORT = 8922
DEFAULT_INSTALL_PORT = 8080
DEFAULT_HOST = "0.0.0.0"
CONFIG_DIR = Path.home() / ".savia" / "bridge"
TOKEN_FILE = CONFIG_DIR / "auth_token"
LOG_FILE = CONFIG_DIR / "bridge.log"
CHAT_LOG_FILE = CONFIG_DIR / "chat.log"
SESSIONS_DIR = CONFIG_DIR / "sessions"
WORKDIRS_BASE = CONFIG_DIR / "workdirs"
USERS_DIR = CONFIG_DIR / "users"
TLS_CERT_FILE = CONFIG_DIR / "cert.pem"
TLS_KEY_FILE = CONFIG_DIR / "key.pem"
TLS_FINGERPRINT_FILE = CONFIG_DIR / "cert_fingerprint.txt"
APK_DIR = CONFIG_DIR / "apk"

# Max log file size before rotation (5 MB)
MAX_LOG_SIZE = 5 * 1024 * 1024

# --- APK Install Page ---

BRIDGE_VERSION = "1.6.0"

# Security constants
MAX_BODY_SIZE = 1_048_576  # 1 MB max request body
MAX_CONCURRENT_STREAMS = 10  # SSE connection limit
RATE_LIMIT_WINDOW = 300  # 5 minutes
RATE_LIMIT_MAX_FAILURES = 5

# A2 FIX: Global counter for active SSE streams
_active_sse_streams = 0
_sse_stream_lock = threading.Lock()

# A3 FIX: Rate limiting on auth attempts (IP -> (count, first_failure_time))
_auth_failures = {}
_auth_failures_lock = threading.Lock()

TEMPLATES_DIR = Path(__file__).resolve().parent / "templates"
LOGO_B64_FILE = CONFIG_DIR / "logo_b64.txt"

def _find_apk() -> Path | None:
    """
    Locate the most recently modified APK file for distribution.

    Searches ~/.savia/bridge/apk/ directory and returns the file with the
    latest modification timestamp. Used by /install and /download/apk endpoints
    to serve the current version.

    Returns:
        Path: Absolute path to the most recent APK file
        None: If no APK files exist in the directory

    Side Effects:
        Creates APK_DIR if it doesn't exist
    """
    APK_DIR.mkdir(parents=True, exist_ok=True)
    apks = sorted(APK_DIR.glob("*.apk"), key=lambda p: p.stat().st_mtime, reverse=True)
    return apks[0] if apks else None

def _get_apk_version(apk_path: Path) -> str:
    """Extract versionName from APK using aapt (best-effort)."""
    try:
        sdk = os.environ.get("ANDROID_HOME") or str(Path.home() / "Android" / "Sdk")
        bt_dir = Path(sdk) / "build-tools"
        if bt_dir.exists():
            versions = sorted(bt_dir.iterdir(), reverse=True)
            if versions:
                aapt = versions[0] / "aapt"
                if aapt.exists():
                    result = subprocess.run(
                        [str(aapt), "dump", "badging", str(apk_path)],
                        capture_output=True, text=True, timeout=10
                    )
                    for token in result.stdout.split():
                        if token.startswith("versionName="):
                            return token.split("=", 1)[1].strip("'\"")
    except Exception:
        pass
    # Fallback: parse filename
    name = apk_path.stem  # e.g. "savia-debug" or "savia-v0.1.0"
    return name

def _get_apk_version_code(apk_path: Path) -> int:
    """
    Extract versionCode from APK using aapt.

    Attempts to use aapt to extract the versionCode from the APK manifest.
    Falls back to parsing the filename (e.g., "savia-v0.2.0-release.apk" -> versionCode 2).

    Args:
        apk_path: Path to the APK file

    Returns:
        int: The versionCode (minimum 1)
    """
    try:
        sdk = os.environ.get("ANDROID_HOME") or str(Path.home() / "Android" / "Sdk")
        bt_dir = Path(sdk) / "build-tools"
        if bt_dir.exists():
            versions = sorted(bt_dir.iterdir(), reverse=True)
            if versions:
                aapt = versions[0] / "aapt"
                if aapt.exists():
                    result = subprocess.run(
                        [str(aapt), "dump", "badging", str(apk_path)],
                        capture_output=True, text=True, timeout=10
                    )
                    for token in result.stdout.split():
                        if token.startswith("versionCode="):
                            try:
                                return int(token.split("=", 1)[1].strip("'\""))
                            except (ValueError, IndexError):
                                pass
    except Exception:
        pass

    # Fallback: parse version from filename (e.g., "savia-v0.2.0" -> extract 2)
    name = apk_path.stem
    match = re.search(r'v(\d+)\.(\d+)\.(\d+)', name)
    if match:
        # Return minor version number as versionCode (e.g., v0.2.0 -> 2)
        return int(match.group(2))
    return 1

def _get_apk_info(apk_path: Path) -> dict:
    """
    Extract comprehensive metadata from an APK file.

    Computes all metadata needed for auto-update endpoints: version, versionCode,
    filename, size in bytes, SHA-256 hash, downloadUrl, releaseNotes, and minAndroidSdk.

    Args:
        apk_path: Path to the APK file to analyze

    Returns:
        dict with keys:
            - version: versionName (e.g., "0.2.0")
            - versionCode: integer version code
            - filename: basename of APK file
            - size: file size in bytes
            - sha256: SHA-256 hash of APK (lowercase hex)
            - downloadUrl: relative path "/update/download"
            - releaseNotes: default release notes
            - minAndroidSdk: minimum Android API level (default 26)
    """
    version = _get_apk_version(apk_path)
    version_code = _get_apk_version_code(apk_path)
    file_size = apk_path.stat().st_size

    # Compute SHA-256 hash
    sha256_hash = hashlib.sha256()
    with open(apk_path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            sha256_hash.update(chunk)
    sha256_hex = sha256_hash.hexdigest()

    return {
        "version": version,
        "versionCode": version_code,
        "filename": apk_path.name,
        "size": file_size,
        "sha256": sha256_hex,
        "downloadUrl": "/update/download",
        "releaseNotes": "Auto-update, project selector, command palette improvements and bug fixes",
        "minAndroidSdk": 26
    }

def _load_logo_b64() -> str:
    """Load the base64-encoded logo PNG. Falls back to a simple SVG."""
    try:
        if LOGO_B64_FILE.exists():
            return f"data:image/png;base64,{LOGO_B64_FILE.read_text().strip()}"
    except Exception:
        pass
    # Fallback: simple SVG circle with "S"
    return "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxMDAgMTAwIj48Y2lyY2xlIGN4PSI1MCIgY3k9IjUwIiByPSI0OCIgZmlsbD0iIzZCNEM5QSIvPjx0ZXh0IHg9IjUwIiB5PSI2MiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZmlsbD0id2hpdGUiIGZvbnQtc2l6ZT0iNDAiIGZvbnQtZmFtaWx5PSJzYW5zLXNlcmlmIiBmb250LXdlaWdodD0iYm9sZCI+UzwvdGV4dD48L3N2Zz4="

def _load_template(name: str) -> str:
    """Load an HTML template from the templates/ directory.

    Args:
        name: Template filename (e.g. 'install.html')

    Returns:
        The raw template string with {{placeholders}} intact.

    Raises:
        FileNotFoundError: If the template file does not exist.
    """
    template_path = TEMPLATES_DIR / name
    if not template_path.exists():
        raise FileNotFoundError(f"Template not found: {template_path}")
    return template_path.read_text(encoding="utf-8")


def _build_install_html(apk: Path | None) -> str:
    """Build the install page HTML by loading the template and injecting data."""
    logo_src = _load_logo_b64()

    if apk:
        size_mb = apk.stat().st_size / (1024 * 1024)
        app_version = _get_apk_version(apk)
        download_section = (
            f'<a href="/download/apk" class="btn">Descargar Savia Mobile</a>\n'
            f'  <div class="apk-info">\n'
            f'    <span class="apk-name">{apk.name}</span>\n'
            f'    <span class="apk-detail">v{app_version} &middot; {size_mb:.1f} MB</span>\n'
            f'  </div>'
        )
    else:
        download_section = (
            '<a class="btn btn-disabled">No disponible</a>\n'
            f'  <p class="apk-info" style="color:#c62828;">No hay APK disponible.<br>'
            f'Coloca el archivo .apk en:<br><code>{APK_DIR}</code></p>'
        )

    template = _load_template("install.html")
    return (
        template
        .replace("{{logo_src}}", logo_src)
        .replace("{{download_section}}", download_section)
        .replace("{{bridge_version}}", BRIDGE_VERSION)
    )

# --- Logging ---

_log_lock = threading.Lock()

def _sanitize(text: str) -> str:
    """
    Sanitize sensitive data from log strings.

    Masks Bearer tokens and token patterns to prevent credential leakage in logs.

    Args:
        text: String potentially containing sensitive data

    Returns:
        String with tokens replaced with placeholders
    """
    if not isinstance(text, str):
        return str(text)
    # Replace Bearer tokens
    text = re.sub(r'Bearer\s+[A-Za-z0-9._\-]+', 'Bearer ***', text)
    # Replace token patterns (e.g., sfYei4... or similar long alphanumeric strings)
    text = re.sub(r'(["\']?)([A-Za-z0-9]{20,})\1', r'\1***\1', text)
    return text

def _rotate_log(filepath: Path):
    """Rotate log file if it exceeds MAX_LOG_SIZE."""
    try:
        if filepath.exists() and filepath.stat().st_size > MAX_LOG_SIZE:
            rotated = filepath.with_suffix(filepath.suffix + ".1")
            if rotated.exists():
                rotated.unlink()
            filepath.rename(rotated)
    except Exception:
        pass

def log(msg: str, level: str = "INFO"):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
    sanitized_msg = _sanitize(msg)
    line = f"[{timestamp}] [{level}] {sanitized_msg}"
    print(line, flush=True)
    with _log_lock:
        try:
            LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
            _rotate_log(LOG_FILE)
            with open(LOG_FILE, "a") as f:
                f.write(line + "\n")
        except Exception:
            pass

def chat_log(msg: str, level: str = "INFO"):
    """Dedicated chat log for request/response detail."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
    sanitized_msg = _sanitize(msg)
    line = f"[{timestamp}] [{level}] {sanitized_msg}"
    with _log_lock:
        try:
            CHAT_LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
            _rotate_log(CHAT_LOG_FILE)
            with open(CHAT_LOG_FILE, "a") as f:
                f.write(line + "\n")
        except Exception:
            pass

# --- SSE Stream Management (A2) ---

def _increment_sse_streams() -> bool:
    """
    Increment active SSE stream counter if under limit.

    Returns:
        bool: True if stream can be opened, False if at limit
    """
    global _active_sse_streams
    with _sse_stream_lock:
        if _active_sse_streams >= MAX_CONCURRENT_STREAMS:
            return False
        _active_sse_streams += 1
        return True

def _decrement_sse_streams():
    """Decrement active SSE stream counter on stream end."""
    global _active_sse_streams
    with _sse_stream_lock:
        if _active_sse_streams > 0:
            _active_sse_streams -= 1

# --- Auth Rate Limiting (A3) ---

def _check_auth_rate_limit(ip: str) -> bool:
    """
    Check if IP has exceeded auth failure rate limit.

    Returns:
        bool: True if IP is not rate limited, False if rate limited
    """
    global _auth_failures
    now = time.time()
    with _auth_failures_lock:
        if ip in _auth_failures:
            count, first_time = _auth_failures[ip]
            # If outside window, reset
            if now - first_time > RATE_LIMIT_WINDOW:
                del _auth_failures[ip]
                return True
            # If at limit, reject
            if count >= RATE_LIMIT_MAX_FAILURES:
                return False
        return True

def _record_auth_failure(ip: str):
    """Record an authentication failure for rate limiting."""
    global _auth_failures
    now = time.time()
    with _auth_failures_lock:
        if ip in _auth_failures:
            count, first_time = _auth_failures[ip]
            _auth_failures[ip] = (count + 1, first_time)
        else:
            _auth_failures[ip] = (1, now)

# --- Auth Token Management ---

def get_or_create_token() -> str:
    """
    Retrieve or generate the authentication token for Savia Bridge.

    If an auth token already exists at ~/.savia/bridge/auth_token, it is loaded
    and returned. Otherwise, a new token is generated using secrets.token_urlsafe()
    with 32 bytes of entropy, saved to disk with restricted permissions (0600),
    and returned.

    The token should be shared with Savia Mobile clients and included in all
    authenticated requests as: 'Authorization: Bearer {token}'

    Returns:
        str: The authentication token (43 characters)

    Side Effects:
        - Creates CONFIG_DIR if it doesn't exist
        - Writes token to TOKEN_FILE with mode 0o600 (owner read/write only)
        - Logs token generation if new token created
    """
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if TOKEN_FILE.exists():
        return TOKEN_FILE.read_text().strip()
    token = secrets.token_urlsafe(32)
    TOKEN_FILE.write_text(token)
    TOKEN_FILE.chmod(0o600)
    log(f"Generated new auth token. Stored in {TOKEN_FILE}")
    return token

# --- Per-User Token Management ---

# In-memory cache: {user_token: slug} for fast lookup
_user_token_cache: dict[str, str] = {}
_user_token_cache_lock = threading.Lock()


def _init_user_token_cache():
    """Load all user tokens into memory at startup."""
    if not USERS_DIR.exists():
        return
    for user_dir in USERS_DIR.iterdir():
        if not user_dir.is_dir():
            continue
        token_file = user_dir / "token"
        if token_file.exists():
            tok = token_file.read_text().strip()
            if tok:
                _user_token_cache[tok] = user_dir.name


def _get_or_create_user(slug: str) -> tuple[str, Path]:
    """
    Get or create a user directory with a per-user token.
    Returns (token, user_dir_path).
    """
    user_dir = USERS_DIR / slug
    user_dir.mkdir(parents=True, exist_ok=True)
    token_file = user_dir / "token"
    if token_file.exists():
        tok = token_file.read_text().strip()
    else:
        tok = secrets.token_urlsafe(32)
        token_file.write_text(tok)
        token_file.chmod(0o600)
        log(f"Generated token for user '{slug}'")
    # Ensure sessions.json exists
    sessions_file = user_dir / "sessions.json"
    if not sessions_file.exists():
        sessions_file.write_text("[]")
    with _user_token_cache_lock:
        _user_token_cache[tok] = slug
    return tok, user_dir


def _validate_user_token(token: str) -> str | None:
    """Return user slug if token matches a per-user token, else None."""
    with _user_token_cache_lock:
        return _user_token_cache.get(token)


def _get_user_profile(slug: str) -> dict | None:
    """Read profile.json for a user. Returns dict or None."""
    profile_file = USERS_DIR / slug / "profile.json"
    if not profile_file.exists():
        return None
    try:
        return json.loads(profile_file.read_text())
    except Exception:
        return None


def _save_user_profile(slug: str, profile: dict):
    """Write profile.json for a user."""
    user_dir = USERS_DIR / slug
    user_dir.mkdir(parents=True, exist_ok=True)
    (user_dir / "profile.json").write_text(json.dumps(profile, indent=2))


def _list_all_users() -> list[dict]:
    """List all users with their profiles."""
    if not USERS_DIR.exists():
        return []
    result = []
    for d in sorted(USERS_DIR.iterdir()):
        if not d.is_dir():
            continue
        profile = _get_user_profile(d.name) or {}
        has_token = (d / "token").exists()
        token_content = (d / "token").read_text().strip() if has_token else ""
        result.append({
            "slug": d.name,
            "name": profile.get("name", d.name),
            "email": profile.get("email", ""),
            "role": profile.get("role", "user"),
            "created": profile.get("created", ""),
            "lastLogin": profile.get("lastLogin", ""),
            "status": "active" if has_token and token_content else "revoked",
        })
    return result


def _get_user_role(slug: str | None) -> str:
    """Get role for a user slug. None (master token) = admin."""
    if slug is None:
        return "admin"
    profile = _get_user_profile(slug)
    return profile.get("role", "user") if profile else "user"


def _create_user(slug: str, name: str = "", email: str = "", role: str = "user") -> str:
    """Create a new user with token. Returns the generated token."""
    token, user_dir = _get_or_create_user(slug)
    profile = {
        "slug": slug, "name": name or slug, "email": email,
        "role": role, "created": datetime.now(tz=timezone.utc).isoformat(),
        "lastLogin": "",
    }
    _save_user_profile(slug, profile)
    return token


def _rotate_user_token(slug: str) -> str | None:
    """Generate a new token for a user. Returns new token or None if user doesn't exist."""
    user_dir = USERS_DIR / slug
    if not user_dir.exists():
        return None
    token_file = user_dir / "token"
    # Remove old token from cache
    if token_file.exists():
        old_token = token_file.read_text().strip()
        with _user_token_cache_lock:
            _user_token_cache.pop(old_token, None)
    # Generate new token
    new_token = secrets.token_urlsafe(32)
    token_file.write_text(new_token)
    token_file.chmod(0o600)
    with _user_token_cache_lock:
        _user_token_cache[new_token] = slug
    log(f"Token rotated for user '{slug}'")
    return new_token


def _revoke_user_token(slug: str) -> bool:
    """Remove a user's token (revoke access). Returns True if successful."""
    token_file = USERS_DIR / slug / "token"
    if not token_file.exists():
        return False
    old_token = token_file.read_text().strip()
    with _user_token_cache_lock:
        _user_token_cache.pop(old_token, None)
    token_file.write_text("")
    log(f"Token revoked for user '{slug}'")
    return True


def _migrate_existing_profiles():
    """On startup, create user entries for existing .claude/profiles/users/."""
    profiles_dir = Path.home() / "savia" / ".claude" / "profiles" / "users"
    if not profiles_dir.exists():
        return
    for d in profiles_dir.iterdir():
        if not d.is_dir() or d.name == "template":
            continue
        user_dir = USERS_DIR / d.name
        if user_dir.exists():
            continue
        # Read identity.md for name/email
        identity = d / "identity.md"
        name, email, role = d.name, "", "user"
        if identity.exists():
            content = identity.read_text()
            for line in content.split("\n"):
                if line.startswith("name:"):
                    name = line.split(":", 1)[1].strip()
                elif line.startswith("email:"):
                    email = line.split(":", 1)[1].strip()
                elif line.startswith("role:"):
                    r = line.split(":", 1)[1].strip().lower()
                    if r == "pm":
                        role = "admin"
        _create_user(d.name, name, email, role)
        log(f"Migrated profile '{d.name}' to Bridge users (role: {role})")


def _get_user_sessions(slug: str) -> list[str]:
    """Return list of session IDs belonging to a user."""
    sessions_file = USERS_DIR / slug / "sessions.json"
    if not sessions_file.exists():
        return []
    try:
        return json.loads(sessions_file.read_text())
    except Exception:
        return []


def _add_user_session(slug: str, session_id: str):
    """Add a session ID to a user's session list."""
    sessions_file = USERS_DIR / slug / "sessions.json"
    sessions = _get_user_sessions(slug)
    if session_id not in sessions:
        sessions.append(session_id)
        sessions_file.write_text(json.dumps(sessions))


def _user_owns_session(slug: str, session_id: str) -> bool:
    """Check if a session belongs to a user."""
    return session_id in _get_user_sessions(slug)


# --- TLS Certificate Management ---

def get_or_create_tls_cert() -> tuple:
    """
    Retrieve or generate a self-signed TLS certificate for HTTPS.

    If a valid TLS certificate and key already exist at ~/.savia/bridge/,
    they are reused along with the cached SHA-256 fingerprint.

    Otherwise, a new self-signed certificate is generated using OpenSSL with:
    - Key size: RSA 2048-bit
    - Validity: 3650 days (10 years)
    - Subject: CN=Savia Bridge/O=Savia/C=ES
    - SubjectAltName: localhost, 127.0.0.1, 0.0.0.0

    The certificate fingerprint is computed and cached for client pinning.

    Returns:
        tuple: (cert_path, key_path, sha256_fingerprint)
            - cert_path (str): Absolute path to cert.pem
            - key_path (str): Absolute path to key.pem
            - sha256_fingerprint (str): SHA-256 hash for certificate pinning

    Raises:
        FileNotFoundError: If openssl is not installed on the system

    Side Effects:
        - Creates CONFIG_DIR and TLS files if needed
        - Sets file permissions: key.pem (0600), cert.pem (0644)
        - Logs certificate generation details
    """
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    if TLS_CERT_FILE.exists() and TLS_KEY_FILE.exists():
        fingerprint = TLS_FINGERPRINT_FILE.read_text().strip() if TLS_FINGERPRINT_FILE.exists() else "unknown"
        return str(TLS_CERT_FILE), str(TLS_KEY_FILE), fingerprint

    log("Generating self-signed TLS certificate...")

    try:
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048",
            "-keyout", str(TLS_KEY_FILE),
            "-out", str(TLS_CERT_FILE),
            "-days", "3650",
            "-nodes",
            "-subj", "/CN=Savia Bridge/O=Savia/C=ES",
            "-addext", "subjectAltName=IP:0.0.0.0,IP:127.0.0.1,DNS:localhost"
        ], check=True, capture_output=True)
    except FileNotFoundError:
        log("openssl not found, cannot generate TLS certificate", "ERROR")
        raise FileNotFoundError("openssl required for TLS certificate generation")

    TLS_KEY_FILE.chmod(0o600)
    TLS_CERT_FILE.chmod(0o644)

    fingerprint = _get_cert_fingerprint()
    TLS_FINGERPRINT_FILE.write_text(fingerprint)

    log(f"TLS certificate generated: {TLS_CERT_FILE}")
    log(f"Certificate fingerprint (SHA-256): {fingerprint}")

    return str(TLS_CERT_FILE), str(TLS_KEY_FILE), fingerprint


def _get_cert_fingerprint() -> str:
    """Get SHA-256 fingerprint of the TLS certificate."""
    try:
        result = subprocess.run(
            ["openssl", "x509", "-in", str(TLS_CERT_FILE), "-fingerprint", "-sha256", "-noout"],
            capture_output=True, text=True, check=True
        )
        return result.stdout.strip().split("=", 1)[-1]
    except Exception:
        import base64
        cert_data = TLS_CERT_FILE.read_bytes()
        lines = cert_data.decode().strip().split("\n")
        der_b64 = "".join(l for l in lines if not l.startswith("-----"))
        der = base64.b64decode(der_b64)
        digest = hashlib.sha256(der).hexdigest()
        return ":".join(digest[i:i+2].upper() for i in range(0, len(digest), 2))


# --- User Profile ---

PROFILE_FILE = CONFIG_DIR / "profile.json"

def _load_user_profile() -> str:
    """Load user profile from ~/.savia/bridge/profile.json.
    Creates a default one if it doesn't exist."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    if not PROFILE_FILE.exists():
        # Auto-detect from system
        import getpass
        username = getpass.getuser()
        default_profile = {
            "name": username,
            "language": "es",
            "role": "Project Manager",
            "notes": "Edita este fichero para personalizar tu perfil."
        }
        PROFILE_FILE.write_text(json.dumps(default_profile, indent=2, ensure_ascii=False))
        log(f"Created default user profile: {PROFILE_FILE}")

    try:
        profile_data = json.loads(PROFILE_FILE.read_text())
        parts = []
        if profile_data.get("name"):
            parts.append(f"- Nombre: {profile_data['name']}")
        if profile_data.get("email"):
            parts.append(f"- Email: {profile_data['email']}")
        if profile_data.get("language"):
            parts.append(f"- Idioma preferido: {profile_data['language']}")
        if profile_data.get("role"):
            parts.append(f"- Rol: {profile_data['role']}")
        if profile_data.get("notes"):
            parts.append(f"- Notas: {profile_data['notes']}")
        return "\n".join(parts) if parts else "No hay perfil configurado."
    except Exception as e:
        log(f"Error loading profile: {e}", "WARN")
        return "No hay perfil configurado."


# --- Claude Code Integration ---

def find_claude_cli() -> str:
    """Find the claude CLI binary."""
    claude_path = shutil.which("claude")
    if claude_path:
        return claude_path
    for path in [
        Path.home() / ".local" / "bin" / "claude",
        Path("/usr/local/bin/claude"),
        Path.home() / ".npm-global" / "bin" / "claude",
        *(
            nvm_bin / "claude"
            for nvm_bin in sorted(
                (Path.home() / ".nvm" / "versions" / "node").glob("*/bin"),
                reverse=True,
            )
        ),
    ]:
        if path.exists():
            return str(path)
    raise FileNotFoundError("Claude Code CLI not found. Install it first: npm install -g @anthropic-ai/claude-code")

# --- Isolated work directories per session ---

# The main workspace directory (where the bridge was started)
_workspace_dir = os.getcwd()

# Selected provider boundary. Claude remains the compatibility default until
# A01c proves two operational adapters.
_selected_cli_adapter_id = "claude"
_selected_cli_adapter = None
_selected_cli_status = {"status": "NOT_VERIFIED", "adapter_id": "claude"}
_adapter_native_sessions: dict[tuple[str, str], str] = {}
_adapter_native_sessions_lock = threading.Lock()


def configure_cli_adapter(adapter_id: str, adapter_factory=adapter_by_id) -> dict:
    """Preflight only the explicitly selected CLI adapter."""
    global _selected_cli_adapter_id, _selected_cli_adapter, _selected_cli_status
    if adapter_id == "claude":
        binary = find_claude_cli()
        status = {"status": "AVAILABLE", "adapter_id": "claude", "binary": binary}
        adapter = None
    else:
        try:
            adapter = adapter_factory(adapter_id)
            status = adapter.preflight()
        except AdapterContractError as error:
            raise RuntimeError(str(error)) from error
        if status.get("status") != "AVAILABLE":
            raise RuntimeError(f"{adapter_id}: {status.get('status', 'NOT_VERIFIED')}")
    _selected_cli_adapter_id = adapter_id
    _selected_cli_adapter = adapter
    _selected_cli_status = status
    return status


def cli_adapter_supports_interactive(adapter_id: str | None = None) -> bool:
    """Permission relay is a legacy Claude-only capability in A01b."""
    return (adapter_id or _selected_cli_adapter_id) == "claude"


def _get_session_workdir(session_id: str, user_slug: str = None) -> str:
    """
    Get or create an isolated working directory for a Claude CLI session.

    Each web/mobile user gets their own cwd so Claude CLI doesn't compete
    for the project-level lock held by an interactive terminal session.
    """
    short_id = session_id.replace("-", "")[:12] if session_id else "default"
    if user_slug:
        base = USERS_DIR / user_slug / "workdirs"
    else:
        base = WORKDIRS_BASE
    base.mkdir(parents=True, exist_ok=True)
    workdir = base / short_id
    workdir.mkdir(parents=True, exist_ok=True)
    return str(workdir)


# Session locks: prevent concurrent CLI calls with the same session
_session_locks: dict[str, threading.Lock] = {}
_session_locks_guard = threading.Lock()


def _parse_frontmatter(text: str) -> dict:
    """Parse YAML frontmatter from markdown text."""
    if not text.startswith("---"):
        return {}
    end = text.find("---", 3)
    if end == -1:
        return {}
    import re
    fm = {}
    for line in text[3:end].strip().split("\n"):
        m = re.match(r'^(\w[\w_]*)\s*:\s*(.+)$', line)
        if m:
            key, val = m.group(1), m.group(2).strip()
            if val.startswith('"') and val.endswith('"'):
                val = val[1:-1]
            elif val.startswith('[') and val.endswith(']'):
                val = [v.strip().strip('"').strip("'") for v in val[1:-1].split(",") if v.strip()]
            elif val.isdigit():
                val = int(val)
            elif val.replace('.', '', 1).isdigit():
                val = float(val)
            fm[key] = val
    return fm


def _parse_backlog_pbis(backlog_dir: Path) -> list:
    """Read PBI markdown files from backlog/pbi/ and return structured data."""
    pbi_dir = backlog_dir / "pbi"
    if not pbi_dir.is_dir():
        return []
    result = []
    for f in sorted(pbi_dir.glob("PBI-*.md")):
        fm = _parse_frontmatter(f.read_text(errors="replace"))
        if fm.get("id"):
            tasks = []
            task_dir = backlog_dir / "tasks"
            pbi_num = fm["id"].split("-")[1] if "-" in str(fm["id"]) else ""
            if task_dir.is_dir() and pbi_num:
                for tf in sorted(task_dir.glob(f"TASK-{pbi_num}-*.md")):
                    tfm = _parse_frontmatter(tf.read_text(errors="replace"))
                    if tfm.get("id"):
                        tasks.append({
                            "id": str(tfm.get("id", "")),
                            "title": str(tfm.get("title", "")),
                            "state": str(tfm.get("state", "New")),
                            "type": str(tfm.get("type", "Development")),
                            "assigned_to": str(tfm.get("assigned_to", "")),
                            "estimated_hours": tfm.get("estimated_hours", 0),
                            "remaining_hours": tfm.get("remaining_hours", 0),
                        })
            result.append({
                "id": str(fm.get("id", "")),
                "title": str(fm.get("title", "")),
                "state": str(fm.get("state", "New")),
                "type": str(fm.get("type", "User Story")),
                "priority": str(fm.get("priority", "3-Medium")),
                "assigned_to": str(fm.get("assigned_to", "")),
                "estimated_hours": fm.get("story_points", 0),
                "tasks": tasks,
            })
    return result


def _parse_backlog_tasks(backlog_dir: Path) -> list:
    """Read all task files from backlog/tasks/."""
    task_dir = backlog_dir / "tasks"
    if not task_dir.is_dir():
        return []
    result = []
    for f in sorted(task_dir.glob("TASK-*.md")):
        fm = _parse_frontmatter(f.read_text(errors="replace"))
        if fm.get("id"):
            result.append({
                "id": str(fm.get("id", "")),
                "title": str(fm.get("title", "")),
                "parent_pbi": str(fm.get("parent_pbi", "")),
                "state": str(fm.get("state", "New")),
                "type": str(fm.get("type", "Development")),
                "assigned_to": str(fm.get("assigned_to", "")),
                "estimated_hours": fm.get("estimated_hours", 0),
                "remaining_hours": fm.get("remaining_hours", 0),
            })
    return result


def _build_dashboard() -> dict:
    """
    Build dashboard data by scanning the PM-Workspace on disk.

    Reads:
    - projects/*/CLAUDE.md for project metadata (name, sprint, velocity)
    - projects/*/test-data/mock-sprint.json for sprint data
    - projects/*/test-data/mock-workitems.json for task data
    - ~/.savia/bridge/profile.json for user name

    Returns a JSON-serializable dict with:
    - user: { name, greeting }
    - projects: [ { id, name, team, currentSprint, health } ]
    - selectedProject: active project details
    - sprint: { name, progress, completedPoints, totalPoints, blockedItems }
    - myTasks: [ { id, title, state, assignee } ]
    - recentActivity: [ string descriptions ]
    - hoursToday: float
    """
    import re
    import datetime

    workspace = Path.home() / "savia"
    projects_dir = workspace / "projects"

    # Load user name from profile
    user_name = "User"
    profile_path = CONFIG_DIR / "profile.json"
    if profile_path.exists():
        try:
            profile = json.loads(profile_path.read_text())
            user_name = profile.get("name", "User")
        except Exception:
            pass

    # Time-of-day greeting
    hour = datetime.datetime.now().hour
    if hour < 12:
        greeting = f"Good morning, {user_name}"
    elif hour < 18:
        greeting = f"Good afternoon, {user_name}"
    else:
        greeting = f"Good evening, {user_name}"

    # Scan projects — include workspace root + projects/ subdirectories
    projects = []
    scan_dirs = []
    # Include workspace root itself if it has CLAUDE.md
    if (workspace / "CLAUDE.md").exists():
        scan_dirs.append(workspace)
    # Include projects/ subdirectories
    if projects_dir.exists():
        scan_dirs.extend(sorted(projects_dir.iterdir()))

    for proj_dir in scan_dirs:
            if not proj_dir.is_dir():
                continue
            claude_md = proj_dir / "CLAUDE.md"
            if not claude_md.exists():
                continue

            # Parse CLAUDE.md constants
            content = claude_md.read_text()
            proj_name = proj_dir.name

            # Extract key constants
            def extract_const(key, default=""):
                m = re.search(rf'{key}\s*=\s*"([^"]*)"', content)
                return m.group(1) if m else default

            def extract_int(key, default=0):
                m = re.search(rf'{key}\s*=\s*(\d+)', content)
                return int(m.group(1)) if m else default

            team = extract_const("TEAM_NAME", proj_name)
            sprint = extract_const("SPRINT_ACTUAL", "")
            velocity = extract_int("VELOCITY_MEDIA_SP", 0)

            # Compute health from sprint data if available
            health = 70  # default
            sprint_data = None
            mock_sprint = proj_dir / "test-data" / "mock-sprint.json"
            if mock_sprint.exists():
                try:
                    sprint_data = json.loads(mock_sprint.read_text())
                    trend = sprint_data.get("burndown", {}).get("trend", "on_track")
                    health = {"on_track": 85, "at_risk": 55, "off_track": 30}.get(trend, 70)
                except Exception:
                    pass

            projects.append({
                "id": proj_name,
                "name": proj_name,
                "team": team,
                "currentSprint": sprint if sprint else None,
                "health": health,
                "_sprintData": sprint_data,  # internal, for selected project
                "_dir": str(proj_dir),
            })

    # Select project (prefer PM-Workspace-related or first with sprint data)
    selected = None
    for p in projects:
        if p.get("_sprintData"):
            selected = p
            break
    if not selected and projects:
        selected = projects[0]

    # Build sprint summary from selected project
    sprint_summary = None
    my_tasks = []
    recent_activity = []
    blocked_count = 0
    hours_today = 0.0

    if selected and selected.get("_sprintData"):
        sd = selected["_sprintData"]

        sprint_info = sd.get("sprint", {})
        summary = sd.get("summary", {})
        burndown = sd.get("burndown", {})
        board_columns = sd.get("board_columns", [])

        total_sp = summary.get("storyPointsCommitted", 0)
        completed_sp = summary.get("storyPointsCompleted", 0)
        progress = (completed_sp / total_sp) if total_sp > 0 else burndown.get("completedPercent", 0) / 100.0

        sprint_summary = {
            "name": sprint_info.get("name", selected.get("currentSprint", "Sprint")),
            "progress": round(progress, 2),
            "completedPoints": completed_sp,
            "totalPoints": total_sp,
            "blockedItems": 0,
            "daysRemaining": sprint_info.get("daysRemaining", 0),
            "goal": sprint_info.get("goal", ""),
        }

        # Count blocked items from alerts
        for alert in sd.get("alerts", []):
            if alert.get("type") == "blocked":
                blocked_count += 1
        sprint_summary["blockedItems"] = blocked_count

        # Extract Active tasks
        active_col = next((c for c in board_columns if c["name"] == "Active"), None)
        if active_col:
            active_ids = active_col.get("items", [])[:3]
            # Load work items if available
            workitems_path = Path(selected["_dir"]) / "test-data" / "mock-workitems.json"
            if workitems_path.exists():
                try:
                    wi_data = json.loads(workitems_path.read_text())
                    for wi in wi_data.get("value", []):
                        if wi["id"] in active_ids:
                            fields = wi.get("fields", {})
                            my_tasks.append({
                                "id": str(wi["id"]),
                                "title": fields.get("System.Title", f"Task #{wi['id']}"),
                                "state": fields.get("System.State", "Active"),
                                "assignee": fields.get("System.AssignedTo", {}).get("displayName", ""),
                            })
                except Exception:
                    pass

            if not my_tasks:
                for tid in active_ids:
                    my_tasks.append({"id": str(tid), "title": f"Task #{tid}", "state": "Active", "assignee": ""})

        # Recent activity from cycle time data
        for ct in sd.get("cycle_time_data", [])[:5]:
            state = ct.get("state", "Done")
            recent_activity.append(f"{ct.get('title', '')} — {state}")

        # Hours from burndown
        hours_today = burndown.get("completedHours", 0.0)

    # Clean internal fields from projects
    clean_projects = []
    for p in projects:
        clean_projects.append({
            "id": p["id"],
            "name": p["name"],
            "team": p["team"],
            "currentSprint": p["currentSprint"],
            "health": p["health"],
        })

    return {
        "user": {"name": user_name, "greeting": greeting},
        "projects": clean_projects,
        "selectedProjectId": selected["id"] if selected else None,
        "sprint": sprint_summary,
        "myTasks": my_tasks,
        "recentActivity": recent_activity,
        "blockedItems": blocked_count,
        "hoursToday": hours_today,
    }


def _is_valid_uuid(val: str) -> bool:
    """Check if a string is a valid UUID (any version)."""
    import re
    return bool(re.match(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        val, re.IGNORECASE
    ))


def _get_session_lock(session_id: str) -> threading.Lock:
    """Get or create a per-session lock to serialize CLI calls."""
    with _session_locks_guard:
        if session_id not in _session_locks:
            _session_locks[session_id] = threading.Lock()
        return _session_locks[session_id]

# Track which session IDs have been used before (need --resume)
# Persisted to disk so bridge restarts don't lose session knowledge
_known_sessions_lock = threading.Lock()
_KNOWN_SESSIONS_FILE = os.path.join(os.path.expanduser("~"), ".savia", "bridge", "known-sessions.json")

def _load_known_sessions() -> set:
    """Load known sessions from disk. Returns empty set on any error."""
    try:
        with open(_KNOWN_SESSIONS_FILE, "r") as f:
            data = json.load(f)
            if isinstance(data, list):
                return set(data)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        pass
    return set()

def _save_known_sessions():
    """Persist known sessions to disk (call with lock held)."""
    try:
        os.makedirs(os.path.dirname(_KNOWN_SESSIONS_FILE), exist_ok=True)
        with open(_KNOWN_SESSIONS_FILE, "w") as f:
            json.dump(sorted(_known_sessions), f)
    except OSError as e:
        log(f"Warning: could not save known sessions: {e}")

_known_sessions: set[str] = _load_known_sessions()


# --- Interactive Session Manager (bidirectional streaming for permissions) ---

class InteractiveSession:
    """
    Manages a long-lived Claude CLI process using bidirectional stream-json protocol.
    Enables permission request/response flow between Claude and the mobile app.

    Protocol: Claude CLI with --input-format stream-json --output-format stream-json
    sends control_request events when it needs tool approval. The bridge forwards these
    as SSE permission_request events to the mobile app, waits for the user's decision
    via POST /chat/permission, then sends control_response back to Claude's stdin.
    """

    def __init__(self, session_id: str, process: subprocess.Popen):
        self.session_id = session_id
        self.process = process
        self.lock = threading.Lock()
        self.permission_event = threading.Event()
        self.permission_response: dict | None = None
        self.pending_request_id: str | None = None
        self.last_activity = _time_module.monotonic()
        self.alive = True

    def send_message(self, message: str, request_id: str = "?"):
        """Write a user message to Claude's stdin as stream-json."""
        msg = json.dumps({"type": "user_message", "content": message})
        chat_log(f"[req:{request_id}] Interactive stdin: {msg[:200]}")
        try:
            self.process.stdin.write(msg + "\n")
            self.process.stdin.flush()
            self.last_activity = _time_module.monotonic()
        except (BrokenPipeError, OSError) as e:
            chat_log(f"[req:{request_id}] Failed to write to stdin: {e}", "ERROR")
            self.alive = False
            raise

    def send_permission_response(self, request_id: str, behavior: str, req_id_log: str = "?"):
        """Send a control_response to Claude's stdin for a pending permission request."""
        response = json.dumps({
            "type": "control_response",
            "response": {
                "subtype": "success",
                "request_id": request_id,
                "response": {"behavior": behavior}
            }
        })
        chat_log(f"[req:{req_id_log}] Permission response -> stdin: {response[:200]}")
        try:
            self.process.stdin.write(response + "\n")
            self.process.stdin.flush()
            self.last_activity = _time_module.monotonic()
        except (BrokenPipeError, OSError) as e:
            chat_log(f"[req:{req_id_log}] Failed to write permission response: {e}", "ERROR")
            self.alive = False
            raise

    def wait_for_permission(self, timeout: float = 120.0) -> dict | None:
        """Block until permission response arrives or timeout."""
        self.permission_event.clear()
        if self.permission_event.wait(timeout=timeout):
            resp = self.permission_response
            self.permission_response = None
            self.pending_request_id = None
            return resp
        return None

    def resolve_permission(self, request_id: str, behavior: str):
        """Called by POST /chat/permission handler to unblock wait_for_permission."""
        self.permission_response = {"request_id": request_id, "behavior": behavior}
        self.permission_event.set()

    def is_alive(self) -> bool:
        return self.alive and self.process.poll() is None

    def kill(self):
        self.alive = False
        try:
            self.process.terminate()
            self.process.wait(timeout=5)
        except Exception:
            try:
                self.process.kill()
                self.process.wait(timeout=2)
            except Exception:
                pass


import time as _time_module

# Global registry of interactive sessions
_interactive_sessions: dict[str, InteractiveSession] = {}
_interactive_sessions_lock = threading.Lock()
_INTERACTIVE_SESSION_TTL = 600  # 10 minutes idle before cleanup


def _get_or_create_interactive_session(
    session_id: str, system_prompt: str = None, request_id: str = "?", user_slug: str = None
) -> InteractiveSession:
    """Get existing interactive session or create new one."""
    with _interactive_sessions_lock:
        session = _interactive_sessions.get(session_id)
        if session and session.is_alive():
            chat_log(f"[req:{request_id}] Reusing interactive session {session_id}")
            return session
        elif session:
            chat_log(f"[req:{request_id}] Interactive session {session_id} dead, recreating")
            session.kill()

    claude_bin = find_claude_cli()
    cmd = [
        claude_bin,
        "--input-format", "stream-json",
        "--output-format", "stream-json",
        "--verbose",
        "--permission-mode", "bypassPermissions",
    ]

    # Use isolated workdir so web sessions don't compete with terminal for project lock
    workdir = _get_session_workdir(session_id, user_slug)
    if workdir != _workspace_dir:
        cmd.extend(["--add-dir", _workspace_dir])

    # Session handling
    with _known_sessions_lock:
        is_new = session_id not in _known_sessions

    if is_new:
        cmd.extend(["--session-id", session_id])
    else:
        cmd.extend(["--resume", session_id])

    if system_prompt and is_new:
        cmd.extend(["--system-prompt", system_prompt])

    chat_log(f"[req:{request_id}] Starting interactive process (workdir={workdir}): {' '.join(cmd[:6])}...")

    process = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        cwd=workdir,
        env={
            **{k: v for k, v in os.environ.items() if k != "CLAUDECODE"},
            "CLAUDE_CODE_ENTRYPOINT": "savia-bridge",
        }
    )

    session = InteractiveSession(session_id, process)

    with _interactive_sessions_lock:
        _interactive_sessions[session_id] = session

    # Mark session as known
    with _known_sessions_lock:
        if session_id not in _known_sessions:
            _known_sessions.add(session_id)
            _save_known_sessions()

    chat_log(f"[req:{request_id}] Interactive process started PID={process.pid}")
    return session


def _cleanup_stale_interactive_sessions():
    """Remove interactive sessions that have been idle too long."""
    now = _time_module.monotonic()
    with _interactive_sessions_lock:
        stale = [
            sid for sid, s in _interactive_sessions.items()
            if (now - s.last_activity > _INTERACTIVE_SESSION_TTL) or not s.is_alive()
        ]
        for sid in stale:
            session = _interactive_sessions.pop(sid, None)
            if session:
                session.kill()
                log(f"Cleaned up stale interactive session {sid}")


def stream_interactive_response(session: InteractiveSession, message: str, request_id: str = "?"):
    """
    Send message to interactive session and yield streaming response chunks.
    Handles control_request events for permission relay.

    Yields dicts with type: text, error, done, permission_request, tool_use
    """
    try:
        session.send_message(message, request_id)
    except Exception as e:
        yield {"type": "error", "text": f"Failed to send message: {e}"}
        yield {"type": "done"}
        return

    full_response = ""
    event_count = 0
    start_time = _time_module.monotonic()
    process_timeout = 300  # 5 minutes max per response

    try:
        for line in session.process.stdout:
            elapsed = _time_module.monotonic() - start_time
            if elapsed > process_timeout:
                chat_log(f"[req:{request_id}] Interactive TIMEOUT after {elapsed:.0f}s", "ERROR")
                yield {"type": "error", "text": f"Request timed out after {process_timeout}s"}
                break

            line = line.strip()
            if not line:
                continue

            chat_log(f"[req:{request_id}] Interactive line: {line[:300]}")

            try:
                data = json.loads(line)
                msg_type = data.get("type", "")

                if msg_type == "assistant" and "message" in data:
                    for block in data["message"].get("content", []):
                        if block.get("type") == "text":
                            text = block.get("text", "")
                            if text:
                                full_response += text
                                event_count += 1
                                yield {"type": "text", "text": text}
                        elif block.get("type") == "tool_use":
                            tool_name = block.get("name", "unknown")
                            event_count += 1
                            yield {"type": "tool_use", "text": f"Using tool: {tool_name}", "tool": tool_name}

                elif msg_type == "content_block_delta":
                    delta = data.get("delta", {})
                    if delta.get("type") == "text_delta":
                        text = delta.get("text", "")
                        if text:
                            full_response += text
                            event_count += 1
                            yield {"type": "text", "text": text}

                elif msg_type == "result":
                    result_text = data.get("result", "")
                    if result_text and not full_response:
                        full_response = result_text
                        event_count += 1
                        yield {"type": "text", "text": result_text}
                    # Result marks end of this response turn
                    chat_log(f"[req:{request_id}] Interactive result received, turn complete")
                    break

                elif msg_type == "control_request":
                    # Permission request from Claude CLI
                    request = data.get("request", {})
                    ctrl_request_id = data.get("request_id", "")
                    subtype = request.get("subtype", "")

                    if subtype == "can_use_tool":
                        tool_name = request.get("tool_name", "unknown")
                        tool_input = request.get("input", {})
                        description = request.get("description", "")

                        chat_log(f"[req:{request_id}] PERMISSION REQUEST: {tool_name} (ctrl_id={ctrl_request_id})")

                        session.pending_request_id = ctrl_request_id
                        event_count += 1

                        yield {
                            "type": "permission_request",
                            "request_id": ctrl_request_id,
                            "tool_name": tool_name,
                            "tool_input": tool_input,
                            "description": description,
                        }

                        # Wait for mobile app to respond via POST /chat/permission
                        chat_log(f"[req:{request_id}] Waiting for permission response...")
                        resp = session.wait_for_permission(timeout=120.0)

                        if resp:
                            behavior = resp.get("behavior", "deny")
                            chat_log(f"[req:{request_id}] Permission resolved: {behavior}")
                            session.send_permission_response(ctrl_request_id, behavior, request_id)
                        else:
                            chat_log(f"[req:{request_id}] Permission TIMEOUT, denying", "WARN")
                            session.send_permission_response(ctrl_request_id, "deny", request_id)
                            yield {"type": "text", "text": "\n[Permission timed out - denied]\n"}
                    else:
                        chat_log(f"[req:{request_id}] Unknown control_request subtype: {subtype}")

                elif msg_type == "error":
                    error_msg = str(data.get("error", {}))
                    chat_log(f"[req:{request_id}] Interactive error: {error_msg}", "ERROR")
                    yield {"type": "error", "text": error_msg}
                    break

                else:
                    chat_log(f"[req:{request_id}] Interactive type={msg_type} (ignored)")

            except json.JSONDecodeError:
                chat_log(f"[req:{request_id}] Interactive non-JSON: {line[:200]}")
                if line:
                    full_response += line
                    yield {"type": "text", "text": line}

    except Exception as e:
        chat_log(f"[req:{request_id}] Interactive stream error: {traceback.format_exc()}", "ERROR")
        yield {"type": "error", "text": str(e)}

    chat_log(f"[req:{request_id}] Interactive done: events={event_count} len={len(full_response)}")
    yield {"type": "done"}


def stream_claude_response(message: str, session_id: str = None, system_prompt: str = None, request_id: str = "?", user_slug: str = None):
    """
    Invoke Claude Code CLI and yield streaming response chunks.

    This is the core function that executes: `claude -p --output-format stream-json [OPTIONS] MESSAGE`
    and yields the response as a stream of JSON event dictionaries.

    Session Handling:
        - First message in a session: passes --session-id (creates new session)
        - Subsequent messages: passes --resume (continues existing session)
        - Per-session locking (via _get_session_lock) prevents race conditions
        - Session state is tracked in _known_sessions set for --resume logic

    Arguments:
        message (str): The user message to send to Claude
        session_id (str, optional): Session ID for continuity. If provided:
            - Uses --session-id on first call, --resume on subsequent calls
            - Enables multi-turn conversations
            - Session data stored in ~/.savia/bridge/sessions/{session_id}/
        system_prompt (str, optional): System prompt for the first message of a session.
            - Only sent on first message (is_new=True)
            - Subsequent messages in the session ignore this
        request_id (str, optional): Request ID for logging/debugging (default: "?")

    Yields:
        dict: JSON event chunks with keys:
            - "type": one of "text", "error", "done"
            - "text": (for type=text/error) The actual text content
            - Other metadata depending on event type

    Logging:
        - Detailed logging to chat.log (message, command, response details)
        - Summary logging to bridge.log

    Side Effects:
        - Adds session_id to _known_sessions after successful response
        - Acquires/releases per-session lock for thread safety
        - Spawns subprocess running Claude CLI

    Examples:
        # Single-shot (no session)
        for chunk in stream_claude_response("Hello"):
            if chunk["type"] == "text":
                print(chunk["text"], end="")

        # Multi-turn conversation
        for chunk in stream_claude_response(
            "First message",
            session_id="user123-abc",
            system_prompt="You are PM..."
        ):
            pass
        # Later: same session, continuing
        for chunk in stream_claude_response(
            "Second message",
            session_id="user123-abc"
        ):
            pass
    """
    claude_bin = find_claude_cli()

    cmd = [claude_bin, "-p", "--verbose", "--output-format", "stream-json"]

    # Use isolated workdir so web sessions don't compete with terminal for project lock
    workdir = _get_session_workdir(session_id, user_slug) if session_id else _workspace_dir
    if workdir != _workspace_dir:
        cmd.extend(["--add-dir", _workspace_dir])

    is_new = True  # Default for no session
    if session_id:
        with _known_sessions_lock:
            is_new = session_id not in _known_sessions

        if is_new:
            cmd.extend(["--session-id", session_id])
        else:
            cmd.extend(["--resume", session_id])

    if system_prompt and is_new:
        # Only send system prompt on first message of a session
        cmd.extend(["--system-prompt", system_prompt])

    # Inject user identity context into every message (--resume ignores --system-prompt)
    if user_slug:
        profile = _get_user_profile(user_slug)
        if profile:
            name = profile.get("name", user_slug)
            role = profile.get("role", "user")
            identity_prefix = f"[Contexto: usuario={name} (@{user_slug}), rol={role}]\n"
            message = identity_prefix + message
    elif not is_new:
        # Master token — use generic profile
        try:
            profile_data = json.loads(PROFILE_FILE.read_text()) if PROFILE_FILE.exists() else {}
            name = profile_data.get("name", "Admin")
            identity_prefix = f"[Contexto: usuario={name}, rol=admin]\n"
            message = identity_prefix + message
        except Exception:
            pass

    cmd.append(message)

    session_mode = "new" if is_new else "resume"
    log(f"[req:{request_id}] Executing ({session_mode}): {claude_bin} -p ... '{message[:80]}'")
    chat_log(f"[req:{request_id}] === NEW REQUEST ===")
    chat_log(f"[req:{request_id}] Message: {message}")
    chat_log(f"[req:{request_id}] Session: {session_id} ({session_mode}), workdir: {workdir}")
    chat_log(f"[req:{request_id}] Command: {' '.join(cmd)}")

    # Acquire per-session lock to prevent concurrent CLI calls
    session_lock = _get_session_lock(session_id) if session_id else None
    if session_lock:
        chat_log(f"[req:{request_id}] Acquiring session lock...")
        session_lock.acquire()
        chat_log(f"[req:{request_id}] Session lock acquired")

    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            cwd=workdir,
            env={
                **{k: v for k, v in os.environ.items() if k != "CLAUDECODE"},
                "CLAUDE_CODE_ENTRYPOINT": "savia-bridge",
            }
        )

        chat_log(f"[req:{request_id}] Process started, PID={process.pid}, cwd={workdir}")

        full_response = ""
        line_count = 0
        event_count = 0
        process_timeout = 300  # 5 minutes max per request
        import time as _time
        start_time = _time.monotonic()

        for line in process.stdout:
            # Check timeout
            elapsed = _time.monotonic() - start_time
            if elapsed > process_timeout:
                chat_log(f"[req:{request_id}] TIMEOUT after {elapsed:.0f}s, killing PID={process.pid}", "ERROR")
                process.kill()
                yield {"type": "error", "text": f"Request timed out after {process_timeout}s"}
                break

            line = line.strip()
            line_count += 1

            if not line:
                continue

            chat_log(f"[req:{request_id}] CLI line #{line_count}: {line[:300]}{'...' if len(line)>300 else ''}")

            try:
                data = json.loads(line)
                msg_type = data.get("type", "")

                if msg_type == "assistant" and "message" in data:
                    content_blocks = data["message"].get("content", [])
                    chat_log(f"[req:{request_id}] type=assistant, {len(content_blocks)} content blocks")
                    for block in content_blocks:
                        if block.get("type") == "text":
                            text = block.get("text", "")
                            if text:
                                full_response += text
                                event_count += 1
                                chat_log(f"[req:{request_id}] -> emit text #{event_count} (len={len(text)}): {text[:100]}")
                                yield {"type": "text", "text": text}
                        elif block.get("type") == "tool_use":
                            tool_name = block.get("name", "unknown")
                            tool_id = block.get("id", "")
                            chat_log(f"[req:{request_id}] -> tool_use: {tool_name} (id={tool_id})")
                            event_count += 1
                            yield {"type": "tool_use", "text": f"Using tool: {tool_name}", "tool": tool_name, "tool_id": tool_id}

                elif msg_type == "content_block_delta":
                    delta = data.get("delta", {})
                    if delta.get("type") == "text_delta":
                        text = delta.get("text", "")
                        if text:
                            full_response += text
                            event_count += 1
                            yield {"type": "text", "text": text}

                elif msg_type == "result":
                    result_text = data.get("result", "")
                    is_error = data.get("is_error", False)
                    chat_log(f"[req:{request_id}] type=result, len={len(result_text)}, accumulated={len(full_response)}, is_error={is_error}")
                    chat_log(f"[req:{request_id}] result content: {result_text[:300]}")

                    if is_error and not full_response:
                        # Resume failed or other CLI error — emit error and invalidate session
                        error_text = result_text or "Session error. Please try again."
                        chat_log(f"[req:{request_id}] -> result is_error, invalidating session", "WARN")
                        if session_id:
                            with _known_sessions_lock:
                                _known_sessions.discard(session_id)
                                _save_known_sessions()
                        event_count += 1
                        yield {"type": "error", "text": error_text}
                    elif result_text and not full_response:
                        full_response = result_text
                        event_count += 1
                        chat_log(f"[req:{request_id}] -> emit result as text #{event_count} (no prior streaming)")
                        yield {"type": "text", "text": result_text}
                    elif result_text:
                        full_response = result_text
                        chat_log(f"[req:{request_id}] -> result skipped (already streamed {len(full_response)} chars)")

                elif msg_type == "error":
                    error_msg = data.get("error", {})
                    error_str = str(error_msg)
                    chat_log(f"[req:{request_id}] type=error: {error_str}", "ERROR")
                    # IMPORTANT: use "text" field so Android can read it
                    yield {"type": "error", "text": error_str}

                else:
                    chat_log(f"[req:{request_id}] type={msg_type} (ignored)")

            except json.JSONDecodeError as e:
                chat_log(f"[req:{request_id}] Non-JSON: {line[:200]}")
                if line:
                    full_response += line
                    event_count += 1
                    yield {"type": "text", "text": line}

        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            chat_log(f"[req:{request_id}] process.wait() timed out, killing PID={process.pid}", "ERROR")
            process.kill()
            process.wait()
        stderr_output = process.stderr.read()

        chat_log(f"[req:{request_id}] Process exit code={process.returncode}")
        if stderr_output:
            chat_log(f"[req:{request_id}] stderr: {stderr_output.strip()[:500]}")

        if process.returncode != 0 and stderr_output:
            error_text = stderr_output.strip()
            chat_log(f"[req:{request_id}] Non-zero exit -> error: {error_text[:200]}", "ERROR")
            # If "already in use" error, mark session as known so next request uses --resume
            if "already in use" in error_text and session_id and is_new:
                with _known_sessions_lock:
                    _known_sessions.add(session_id)
                    _save_known_sessions()
                chat_log(f"[req:{request_id}] Session {session_id} marked as known after 'already in use' error")
                yield {"type": "error", "text": "Session conflict detected. Please resend your message."}
            else:
                yield {"type": "error", "text": error_text}

        # Mark session as known for future --resume usage (persisted to disk)
        if session_id and full_response:
            with _known_sessions_lock:
                if session_id not in _known_sessions:
                    _known_sessions.add(session_id)
                    _save_known_sessions()
                    chat_log(f"[req:{request_id}] Session {session_id} marked as known (persisted)")
                else:
                    chat_log(f"[req:{request_id}] Session {session_id} already known")

        chat_log(f"[req:{request_id}] === DONE === lines={line_count} events={event_count} response_len={len(full_response)}")
        yield {"type": "done"}

    except FileNotFoundError:
        chat_log(f"[req:{request_id}] Claude CLI not found!", "ERROR")
        yield {"type": "error", "text": "Claude Code CLI not found"}
        yield {"type": "done"}
    except Exception as e:
        chat_log(f"[req:{request_id}] Exception: {traceback.format_exc()}", "ERROR")
        yield {"type": "error", "text": str(e)}
        yield {"type": "done"}
    finally:
        # Always release session lock
        if session_lock:
            session_lock.release()
            chat_log(f"[req:{request_id}] Session lock released")


def _adapter_message(message: str, user_slug: str | None, is_new: bool) -> str:
    """Preserve bridge identity context without leaking it into the adapter API."""
    if user_slug:
        profile = _get_user_profile(user_slug)
        if profile:
            name = profile.get("name", user_slug)
            role = profile.get("role", "user")
            return f"[Contexto: usuario={name} (@{user_slug}), rol={role}]\n{message}"
    elif not is_new:
        try:
            profile = json.loads(PROFILE_FILE.read_text()) if PROFILE_FILE.exists() else {}
            return f"[Contexto: usuario={profile.get('name', 'Admin')}, rol=admin]\n{message}"
        except Exception:
            pass
    return message


def stream_cli_response(message: str, session_id: str = None,
                        system_prompt: str = None, request_id: str = "?",
                        user_slug: str = None):
    """Stream the selected adapter; success requires a verified done event."""
    if _selected_cli_adapter_id == "claude":
        yield from stream_claude_response(
            message, session_id, system_prompt, request_id, user_slug
        )
        return
    if _selected_cli_adapter is None:
        yield {"type": "error", "text": "CLI adapter NOT_VERIFIED"}
        return

    key = (_selected_cli_adapter_id, session_id) if session_id else None
    session_lock = _get_session_lock(session_id) if session_id else None
    pending_native_ref = None
    saw_done = False
    saw_error = False
    lock_acquired = False
    try:
        if session_lock:
            session_lock.acquire()
            lock_acquired = True
        with _adapter_native_sessions_lock:
            native_ref = _adapter_native_sessions.get(key) if key else None
        # Alternative adapters operate on the bridge workspace. Claude's
        # provider-specific isolated directory remains in the legacy path.
        workdir = _workspace_dir
        request = BridgeRequest(
            message=_adapter_message(message, user_slug, native_ref is None),
            system_prompt=system_prompt if native_ref is None else None,
            bridge_session_id=session_id,
            workdir=str(Path(workdir).resolve()),
            authority_ceiling="L2",
            request_id=request_id,
            persistent=bool(session_id),
        )
        command = (_selected_cli_adapter.resume_command(request, native_ref)
                   if native_ref else _selected_cli_adapter.start_command(request))
        process = subprocess.Popen(
            command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            bufsize=1, cwd=workdir,
        )
        chat_log(f"[req:{request_id}] Adapter process started: {_selected_cli_adapter_id}")
        for line in process.stdout:
            try:
                batch = _selected_cli_adapter.translate(line.strip())
            except AdapterContractError as error:
                saw_error = True
                yield {"type": "error", "text": str(error)}
                process.kill()
                break
            pending_native_ref = batch.native_session_ref or pending_native_ref
            for event in batch.events:
                if event.get("type") == "done":
                    saw_done = True
                elif event.get("type") == "error":
                    saw_error = True
                    yield event
                else:
                    yield event
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            saw_error = True
            yield {"type": "error", "text": "CLI process did not exit"}
        stderr_output = process.stderr.read().strip()
        if process.returncode != 0 and not saw_error:
            saw_error = True
            yield {"type": "error", "text": stderr_output or "CLI process failed"}
        if saw_done and not saw_error:
            if key and pending_native_ref:
                with _adapter_native_sessions_lock:
                    _adapter_native_sessions[key] = pending_native_ref
            yield {"type": "done"}
        elif not saw_error:
            yield {"type": "error", "text": "NOT_VERIFIED: missing completion event"}
    except (AdapterContractError, OSError, subprocess.SubprocessError) as error:
        yield {"type": "error", "text": str(error)}
    finally:
        if session_lock and lock_acquired:
            session_lock.release()

# --- HTTP Server ---

class SaviaBridgeHandler(http.server.BaseHTTPRequestHandler):
    """
    HTTP/HTTPS request handler for Savia Bridge endpoints.

    This class processes incoming requests from the Savia Mobile app and
    routes them to the appropriate handler (chat, health, sessions, etc.).

    Class Attributes:
        auth_token (str): Bearer token for authentication (set by server init)
        system_prompt (str): Default system prompt for Claude (set by server init)
        _request_counter (int): Incremental counter for request IDs
        _counter_lock (threading.Lock): Protects counter during concurrent access

    Key Methods:
        do_POST(): Handle POST /chat requests
        do_GET(): Handle GET /health, /sessions, /install, /download/apk
        do_DELETE(): Handle DELETE /sessions
        _check_auth(): Validate Bearer token
        log_message(): Override HTTPServer logging

    Authentication:
        All endpoints except /install and /download/apk require valid Bearer token
        in Authorization header: 'Authorization: Bearer {token}'
    """

    auth_token = None
    system_prompt = None
    _request_counter = 0
    _counter_lock = threading.Lock()

    @classmethod
    def _next_request_id(cls) -> str:
        with cls._counter_lock:
            cls._request_counter += 1
            return f"{cls._request_counter:06d}"

    def log_message(self, format, *args):
        log(f"{self.address_string()} - {format % args}", "HTTP")

    # Set by _check_auth: slug of authenticated user, or None for master token
    _auth_user: str | None = None

    def _check_auth(self) -> bool:
        """
        Two-tier auth: master token (admin) or per-user token.
        Sets self._auth_user to the user slug if per-user, None if master.
        """
        self._auth_user = None
        client_ip = self.address_string().split(':')[0]
        if not _check_auth_rate_limit(client_ip):
            log(f"Auth rate limit exceeded for IP {client_ip}", "SECURITY")
            self._send_json({"error": "Too many failed authentication attempts"}, 429)
            return False

        if not self.auth_token:
            return True

        token = None
        auth_header = self.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            token = auth_header[7:]
        else:
            parsed = urlparse(self.path)
            params = parse_qs(parsed.query)
            token = params.get("token", [None])[0]

        if not token:
            _record_auth_failure(client_ip)
            return False

        # Check master token first
        if secrets.compare_digest(token, self.auth_token):
            self._auth_user = None
            return True

        # Check per-user tokens
        user_slug = _validate_user_token(token)
        if user_slug:
            self._auth_user = user_slug
            return True

        _record_auth_failure(client_ip)
        return False

    def _send_security_headers(self):
        """A4 FIX: Add standard security headers to all responses."""
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("X-XSS-Protection", "1; mode=block")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")

    def _send_json(self, data: dict, status: int = 200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self._send_cors_headers()
        self._send_security_headers()
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def _send_cors_headers(self):
        """A5 FIX: Restrict CORS to local network origins only."""
        origin = self.headers.get("Origin", "")
        allowed_patterns = ("http://localhost", "https://localhost",
                            "http://127.0.0.1", "https://127.0.0.1",
                            "http://192.168.", "https://192.168.",
                            "http://10.", "https://10.",
                            "http://100.", "https://100.",
                            "http://172.", "https://172.",
                            "http://lima", "https://lima")
        if any(origin.startswith(p) for p in allowed_patterns):
            self.send_header("Access-Control-Allow-Origin", origin)
        else:
            self.send_header("Access-Control-Allow-Origin", "https://localhost")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Vary", "Origin")

    def do_OPTIONS(self):
        self.send_response(204)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/health":
            if _selected_cli_status.get("status") == "AVAILABLE":
                self._send_json({
                    "status": "ok",
                    "cli_adapter": _selected_cli_adapter_id,
                    "adapter_status": "AVAILABLE",
                    "version": BRIDGE_VERSION,
                    "tls": True,
                    "timestamp": datetime.now().isoformat()
                })
            else:
                self._send_json({
                    "status": "error",
                    "message": "Selected CLI adapter is not verified"
                }, 503)
            return

        if parsed.path == "/sessions":
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            # Per-user: return only their sessions; master: return all
            if self._auth_user:
                session_ids = _get_user_sessions(self._auth_user)
                sessions = [{"id": sid} for sid in session_ids]
            else:
                sessions = []
                if SESSIONS_DIR.exists():
                    for d in SESSIONS_DIR.iterdir():
                        if d.is_dir():
                            sessions.append({
                                "id": d.name,
                                "created": datetime.fromtimestamp(d.stat().st_ctime).isoformat()
                            })
            self._send_json({"sessions": sessions})
            return

        if parsed.path == "/logs":
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            params = parse_qs(parsed.query)
            n = int(params.get("n", ["100"])[0])
            log_type = params.get("type", ["chat"])[0]
            target = CHAT_LOG_FILE if log_type == "chat" else LOG_FILE
            lines = []
            if target.exists():
                with open(target) as f:
                    all_lines = f.readlines()
                    lines = all_lines[-n:]
            self._send_json({"lines": [l.rstrip() for l in lines], "file": str(target)})
            return

        # --- Auto-Update Endpoints (no auth required) ---
        if parsed.path == "/update/check":
            """
            GET /update/check — Check for available APK update.

            Returns JSON with current APK metadata:
            {
                "version": "0.2.0",
                "versionCode": 2,
                "filename": "savia-v0.2.0-release.apk",
                "size": 12345678,
                "sha256": "abc123...",
                "downloadUrl": "/update/download",
                "releaseNotes": "Auto-update, project selector...",
                "minAndroidSdk": 26
            }

            Returns 404 if no APK is available.
            """
            apk = _find_apk()
            if not apk:
                self._send_json({"error": "No APK available"}, 404)
                return
            info = _get_apk_info(apk)
            self._send_json(info)
            return

        if parsed.path == "/update/download":
            """
            GET /update/download — Download the current APK file.

            Same as /download/apk but at /update/ path for auto-update clients.
            Returns the APK binary with appropriate Content-Type and Content-Disposition.

            Returns 404 if no APK is available.
            """
            apk = _find_apk()
            if not apk:
                self._send_json({"error": "No APK available"}, 404)
                return
            # A1 FIX: Path traversal check — ensure APK is within APK_DIR
            try:
                apk_resolved = apk.resolve()
                apk_dir_resolved = APK_DIR.resolve()
                if not str(apk_resolved).startswith(str(apk_dir_resolved)):
                    log(f"Path traversal attempt blocked: {apk_resolved}", "SECURITY")
                    self._send_json({"error": "Forbidden"}, 403)
                    return
            except Exception as e:
                log(f"Path validation error: {e}", "ERROR")
                self._send_json({"error": "Internal error"}, 500)
                return
            log(f"APK download via /update: {apk.name} ({apk.stat().st_size} bytes) to {self.address_string()}")
            self.send_response(200)
            self.send_header("Content-Type", "application/vnd.android.package-archive")
            self.send_header("Content-Disposition", f'attachment; filename="{apk.name}"')
            self.send_header("Content-Length", str(apk.stat().st_size))
            self.end_headers()
            with open(apk, "rb") as f:
                shutil.copyfileobj(f, self.wfile)
            return

        # --- APK Install Page (no auth required) ---
        if parsed.path == "/install":
            html = _build_install_html(_find_apk())
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(html.encode())
            return

        if parsed.path == "/download/apk":
            apk = _find_apk()
            if not apk:
                self._send_json({"error": "No APK available"}, 404)
                return
            # A1 FIX: Path traversal check — ensure APK is within APK_DIR
            try:
                apk_resolved = apk.resolve()
                apk_dir_resolved = APK_DIR.resolve()
                if not str(apk_resolved).startswith(str(apk_dir_resolved)):
                    log(f"Path traversal attempt blocked: {apk_resolved}", "SECURITY")
                    self._send_json({"error": "Forbidden"}, 403)
                    return
            except Exception as e:
                log(f"Path validation error: {e}", "ERROR")
                self._send_json({"error": "Internal error"}, 500)
                return
            log(f"APK download: {apk.name} ({apk.stat().st_size} bytes) to {self.address_string()}")
            self.send_response(200)
            self.send_header("Content-Type", "application/vnd.android.package-archive")
            self.send_header("Content-Disposition", f'attachment; filename="{apk.name}"')
            self.send_header("Content-Length", str(apk.stat().st_size))
            self.end_headers()
            with open(apk, "rb") as f:
                shutil.copyfileobj(f, self.wfile)
            return

        if parsed.path == "/profile":
            # C5 FIX: Require auth for sensitive endpoints
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            # Read from git config
            name = subprocess.run(['git', 'config', '--global', 'user.name'], capture_output=True, text=True, timeout=2).stdout.strip()
            email = subprocess.run(['git', 'config', '--global', 'user.email'], capture_output=True, text=True, timeout=2).stdout.strip()

            # Try to read company name from .claude/profiles/company/identity.md
            company = ""
            role = "Developer"
            identity_path = Path.home() / "savia" / ".claude" / "profiles" / "company" / "identity.md"
            if identity_path.exists():
                try:
                    content = identity_path.read_text()
                    for line in content.split('\n'):
                        if line.startswith('company:') or line.startswith('name:'):
                            company = line.split(':', 1)[1].strip()
                            break
                except Exception:
                    pass

            # Start with git config + company data as base
            profile_data = {
                "name": name or "User",
                "email": email or "",
                "company": company,
                "role": role,
                "language": "en",
                "work_hours_start": "09:00",
                "work_hours_end": "17:30",
                "lunch_break": "12:30",
                "break_strategy": "pomodoro",
                "detail_level": "standard",
                "alert_style": "desktop",
                "output_mode": "hybrid",
                "theme": "auto",
                "notes": "",
                "accessibility": {}
            }

            # Merge with bridge profile.json (takes priority for richer fields)
            profile_path = CONFIG_DIR / "profile.json"
            if profile_path.exists():
                try:
                    stored_data = json.loads(profile_path.read_text())
                    # Update all fields present in stored profile
                    for key in ("name", "email", "role", "language", "notes",
                                "work_hours_start", "work_hours_end", "lunch_break",
                                "break_strategy", "detail_level", "alert_style",
                                "output_mode", "theme", "accessibility"):
                        if key in stored_data:
                            profile_data[key] = stored_data[key]
                except Exception:
                    pass

            self._send_json(profile_data)
            return

        if parsed.path == "/company":
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            company_dir = Path.home() / "savia" / ".claude" / "profiles" / "company"
            if not company_dir.exists() or not any(company_dir.glob("*.md")):
                self._send_json({"status": "not_configured"})
                return

            result = {"status": "configured"}
            for section_file in ["identity.md", "structure.md", "strategy.md", "policies.md", "technology.md", "vertical.md"]:
                filepath = company_dir / section_file
                if filepath.exists():
                    try:
                        content = filepath.read_text()
                        section_name = section_file.replace(".md", "")
                        # Parse simple YAML frontmatter with injection protection
                        section_data = {}
                        if content.startswith("---"):
                            parts = content.split("---", 2)
                            if len(parts) >= 3:
                                for line in parts[1].strip().split('\n'):
                                    if ':' in line:
                                        key, val = line.split(':', 1)
                                        key = key.strip()
                                        val = val.strip()
                                        # Sanitize: quote special YAML characters
                                        if any(c in val for c in (':', '{', '}', '[', ']', '&', '*', '#', '|', '>')):
                                            val = f'"{val}"'
                                        section_data[key] = val.strip('"').strip("'")
                                section_data["content"] = parts[2].strip()
                        else:
                            section_data["content"] = content.strip()
                        result[section_name] = section_data
                    except Exception as e:
                        log(f"Warning: Could not parse {section_file}: {e}")

            self._send_json(result)
            return

        if parsed.path == "/git-config":
            """GET /git-config — Read git global configuration (name, email, PAT status)."""
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            try:
                name = subprocess.run(['git', 'config', '--global', 'user.name'],
                                      capture_output=True, text=True, timeout=2).stdout.strip()
                email = subprocess.run(['git', 'config', '--global', 'user.email'],
                                       capture_output=True, text=True, timeout=2).stdout.strip()
                # Check if credential helper is configured
                cred_helper = subprocess.run(['git', 'config', '--global', 'credential.helper'],
                                             capture_output=True, text=True, timeout=2).stdout.strip()
                # Check for PAT in environment or git credentials (never expose the actual token)
                pat_configured = bool(os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN"))
                # Check for stored credentials via git credential manager
                if not pat_configured and cred_helper:
                    pat_configured = True  # Credential helper implies some auth is configured

                # Check remote URL for repo info
                remote_url = ""
                try:
                    remote_url = subprocess.run(['git', 'config', '--get', 'remote.origin.url'],
                                                capture_output=True, text=True, timeout=2,
                                                cwd=str(Path.home() / "savia")).stdout.strip()
                except Exception:
                    pass

                self._send_json({
                    "name": name,
                    "email": email,
                    "credential_helper": cred_helper,
                    "pat_configured": pat_configured,
                    "remote_url": remote_url
                })
            except Exception as e:
                log(f"Error reading git config: {e}", "ERROR")
                self._send_json({"error": str(e)}, 500)
            return

        if parsed.path == "/team":
            """GET /team — Read team configuration from .claude/profiles/users/."""
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            team_dir = Path.home() / "savia" / ".claude" / "profiles" / "users"
            members = []

            if team_dir.exists():
                for user_dir in sorted(team_dir.iterdir()):
                    if user_dir.is_dir():
                        member = {"slug": user_dir.name}
                        identity_file = user_dir / "identity.md"
                        if identity_file.exists():
                            try:
                                content = identity_file.read_text()
                                if content.startswith("---"):
                                    parts = content.split("---", 2)
                                    if len(parts) >= 3:
                                        for line in parts[1].strip().split('\n'):
                                            if ':' in line:
                                                key, val = line.split(':', 1)
                                                member[key.strip()] = val.strip().strip('"').strip("'")
                            except Exception:
                                pass
                        # Also check for other fragments
                        for fragment in ["workflow.md", "tools.md", "projects.md"]:
                            fpath = user_dir / fragment
                            if fpath.exists():
                                member[f"has_{fragment.replace('.md', '')}"] = True
                        # Skip template/empty profiles
                        if member.get("name") and user_dir.name != "template":
                            members.append(member)

            self._send_json({
                "status": "configured" if members else "not_configured",
                "members": members,
                "count": len(members)
            })
            return

        if parsed.path == "/connectors":
            """GET /connectors — Read configured external service connectors."""
            connectors_file = Path.home() / "savia" / ".claude" / "connectors.json"
            if connectors_file.exists():
                try:
                    data = json.loads(connectors_file.read_text())
                    self._send_json({"status": "configured", "connectors": data})
                except Exception as e:
                    self._send_json({"error": str(e)}, 500)
            else:
                self._send_json({"status": "not_configured", "connectors": {}})
            return

        if parsed.path == "/dashboard":
            try:
                data = _build_dashboard()
                self._send_json(data)
            except Exception as e:
                log(f"Dashboard error: {traceback.format_exc()}", "ERROR")
                self._send_json({"error": str(e)}, 500)
            return

        if parsed.path == "/auth/me":
            """GET /auth/me — Returns authenticated user info."""
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            if self._auth_user is None:
                self._send_json({"slug": "admin", "role": "admin", "name": "Admin"})
            else:
                _p = _get_user_profile(self._auth_user) or {}
                self._send_json({"slug": self._auth_user, "role": _p.get("role", "user"), "name": _p.get("name", self._auth_user)})
            return

        if parsed.path == "/users":
            """GET /users — List all users (admin only)."""
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            if _get_user_role(self._auth_user) != "admin":
                self._send_json({"error": "Admin access required"}, 403)
                return
            self._send_json({"users": _list_all_users()})
            return

        if parsed.path.startswith("/users/") and parsed.path.endswith("/role"):
            """GET /users/{slug}/role — Get user role (for auth store)."""
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            slug = parsed.path.split("/")[2]
            profile = _get_user_profile(slug)
            role = profile.get("role", "user") if profile else "user"
            self._send_json({"slug": slug, "role": role})
            return

        if parsed.path == "/projects":
            """GET /projects — List available projects from projects/ directory."""
            try:
                workspace = Path(os.environ.get("SAVIA_WORKSPACE", Path.home() / "savia"))
                projects_dir = workspace / "projects"
                result = []
                has_claude = (workspace / "CLAUDE.md").exists()
                result.append({
                    "id": "_workspace",
                    "name": "Savia (workspace)",
                    "path": ".",
                    "hasClaude": has_claude,
                    "hasBacklog": False,
                    "health": "healthy",
                })
                if projects_dir.is_dir():
                    for d in sorted(projects_dir.iterdir()):
                        if d.is_dir() and not d.name.startswith("."):
                            result.append({
                                "id": d.name,
                                "name": d.name,
                                "path": f"projects/{d.name}",
                                "hasClaude": (d / "CLAUDE.md").exists(),
                                "hasBacklog": (d / "backlog").is_dir(),
                                "health": "healthy",
                            })
                self._send_json(result)
            except Exception as e:
                log(f"Projects error: {e}", "ERROR")
                self._send_json({"error": str(e)}, 500)
            return

        if parsed.path.startswith("/backlog"):
            """GET /backlog?project={id} — PBIs and tasks from project backlog."""
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            params = parse_qs(parsed.query)
            project_id = params.get("project", ["_workspace"])[0]
            try:
                workspace = Path(os.environ.get("SAVIA_WORKSPACE", Path.home() / "savia"))
                if project_id == "_workspace":
                    backlog_dir = workspace / "backlog"
                else:
                    backlog_dir = workspace / "projects" / project_id / "backlog"
                pbis = _parse_backlog_pbis(backlog_dir)
                tasks = _parse_backlog_tasks(backlog_dir)
                self._send_json({"pbis": pbis, "tasks": tasks})
            except Exception as e:
                log(f"Backlog error: {e}", "ERROR")
                self._send_json({"pbis": [], "tasks": []})
            return

        if parsed.path == "/openapi.json":
            spec_path = Path(__file__).resolve().parent / "openapi.yaml"
            if not spec_path.exists():
                self._send_json({"error": "OpenAPI spec not found"}, 404)
                return
            # Serve as YAML since we can't depend on PyYAML for JSON conversion
            content = spec_path.read_text()
            self.send_response(200)
            self.send_header("Content-Type", "application/x-yaml")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(content.encode())
            return

        # --- New Data Endpoints (no auth required) ---

        if parsed.path.startswith("/kanban"):
            """GET /kanban?project={projectId} — Kanban board with columns grouped by state."""
            params = parse_qs(parsed.query)
            project_id = params.get("project", [None])[0]

            if not project_id:
                self._send_json({"error": "Missing project parameter"}, 400)
                return

            project_dir = Path.home() / "savia" / "projects" / project_id
            if not project_dir.exists():
                self._send_json({"error": f"Project {project_id} not found"}, 404)
                return

            workitems_path = project_dir / "test-data" / "mock-workitems.json"
            if not workitems_path.exists():
                self._send_json({"error": "Mock data not found"}, 404)
                return

            try:
                wi_data = json.loads(workitems_path.read_text())
                board = {}

                for wi in wi_data.get("value", []):
                    fields = wi.get("fields", {})
                    state = fields.get("System.State", "New")

                    if state not in board:
                        board[state] = {
                            "name": state,
                            "items": [],
                            "wipLimit": None
                        }

                    board[state]["items"].append({
                        "id": str(wi["id"]),
                        "title": fields.get("System.Title", f"Task #{wi['id']}"),
                        "assignee": fields.get("System.AssignedTo", {}).get("displayName", ""),
                        "storyPoints": fields.get("Microsoft.VSTS.Scheduling.StoryPoints", 0),
                        "state": state,
                        "type": fields.get("System.WorkItemType", "Task")
                    })

                # Define WIP limits by state
                wip_limits = {
                    "Active": 3,
                    "New": None,
                    "Committed": None,
                    "Done": None
                }

                for state_name, limit in wip_limits.items():
                    if state_name in board:
                        board[state_name]["wipLimit"] = limit

                # Return as ordered list
                result = [
                    {"name": "New", "items": board.get("New", {}).get("items", []), "wipLimit": None},
                    {"name": "Active", "items": board.get("Active", {}).get("items", []), "wipLimit": 3},
                    {"name": "Committed", "items": board.get("Committed", {}).get("items", []), "wipLimit": None},
                    {"name": "Done", "items": board.get("Done", {}).get("items", []), "wipLimit": None}
                ]

                self._send_json(result)
            except Exception as e:
                log(f"Error processing kanban for {project_id}: {e}", "ERROR")
                self._send_json({"error": str(e)}, 500)
            return

        if parsed.path.startswith("/timelog"):
            """GET /timelog?project={projectId}&date={YYYY-MM-DD} — Time entries from CompletedWork."""
            params = parse_qs(parsed.query)
            project_id = params.get("project", [None])[0]
            date_str = params.get("date", [None])[0]

            if not project_id:
                self._send_json({"error": "Missing project parameter"}, 400)
                return

            project_dir = Path.home() / "savia" / "projects" / project_id
            if not project_dir.exists():
                self._send_json({"error": f"Project {project_id} not found"}, 404)
                return

            workitems_path = project_dir / "test-data" / "mock-workitems.json"
            if not workitems_path.exists():
                self._send_json({"error": "Mock data not found"}, 404)
                return

            try:
                wi_data = json.loads(workitems_path.read_text())
                timelog = []

                for wi in wi_data.get("value", []):
                    fields = wi.get("fields", {})
                    completed_work = fields.get("Microsoft.VSTS.Scheduling.CompletedWork", 0)

                    if completed_work > 0:
                        timelog.append({
                            "id": str(wi["id"]),
                            "taskId": str(wi["id"]),
                            "taskTitle": fields.get("System.Title", f"Task #{wi['id']}"),
                            "hours": completed_work,
                            "date": date_str or "2026-03-09",
                            "note": None
                        })

                self._send_json(timelog)
            except Exception as e:
                log(f"Error processing timelog for {project_id}: {e}", "ERROR")
                self._send_json({"error": str(e)}, 500)
            return

        if parsed.path.startswith("/approvals"):
            """GET /approvals?project={projectId} — Mock approval requests."""
            params = parse_qs(parsed.query)
            project_id = params.get("project", [None])[0]

            if not project_id:
                self._send_json({"error": "Missing project parameter"}, 400)
                return

            project_dir = Path.home() / "savia" / "projects" / project_id
            if not project_dir.exists():
                self._send_json({"error": f"Project {project_id} not found"}, 404)
                return

            workitems_path = project_dir / "test-data" / "mock-workitems.json"

            # Generate mock approvals if project has work items
            approvals = []
            if workitems_path.exists():
                try:
                    wi_data = json.loads(workitems_path.read_text())
                    if wi_data.get("value"):
                        approvals = [
                            {
                                "id": "pr-1",
                                "type": "PULL_REQUEST",
                                "title": "feat: implement CRUD salas",
                                "description": "Implements complete CRUD operations for room management via REST API endpoints.",
                                "requester": "Carlos Mendoza",
                                "createdAt": "2026-03-08T14:00:00Z",
                                "estimatedCost": None
                            },
                            {
                                "id": "infra-1",
                                "type": "INFRASTRUCTURE",
                                "title": "Scale DB to 4 vCPU",
                                "description": "Increase database instance resources to handle sprint 2026-04 load.",
                                "requester": "DevOps Bot",
                                "createdAt": "2026-03-09T10:00:00Z",
                                "estimatedCost": "$45/month"
                            }
                        ]
                except Exception:
                    pass

            self._send_json(approvals)
            return

        # ─── Reports: delegate to savia-bridge-reports module ───
        if parsed.path.startswith("/reports/"):
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            params = parse_qs(parsed.query)
            project_id = params.get("project", ["default"])[0]
            report_name = parsed.path.split("/reports/", 1)[1].rstrip("/")
            try:
                from savia_bridge_reports import (
                    velocity, burndown, dora, team_workload,
                    quality, debt, cycle_time, portfolio,
                )
                dispatch = {
                    "velocity": lambda: velocity(project_id),
                    "burndown": lambda: burndown(project_id),
                    "dora": lambda: dora(project_id),
                    "team-workload": lambda: team_workload(project_id),
                    "quality": lambda: quality(project_id),
                    "debt": lambda: debt(project_id),
                    "cycle-time": lambda: cycle_time(project_id),
                    "portfolio": lambda: portfolio(),
                }
                handler = dispatch.get(report_name)
                if handler:
                    self._send_json(handler())
                else:
                    self._send_json({"error": f"Unknown report: {report_name}"}, 404)
            except ImportError:
                self._send_json({"error": "Reports module not available"}, 500)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
            return

        # ─── File Browser: list directory contents ───
        if parsed.path == "/files":
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            params = parse_qs(parsed.query)
            rel_path = params.get("path", [""])[0]
            workspace = Path.home() / "savia"
            target = (workspace / rel_path).resolve()
            # Security: prevent path traversal outside workspace
            if not str(target).startswith(str(workspace)):
                self._send_json({"error": "Path traversal blocked"}, 403)
                return
            if not target.exists():
                self._send_json({"error": "Path not found"}, 404)
                return
            if target.is_file():
                stat = target.stat()
                self._send_json({
                    "type": "file",
                    "name": target.name,
                    "path": str(target.relative_to(workspace)),
                    "size": stat.st_size,
                    "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    "extension": target.suffix
                })
                return
            # Directory listing
            entries = []
            try:
                for item in sorted(target.iterdir(), key=lambda p: (p.is_file(), p.name.lower())):
                    if item.name.startswith(".") and item.name not in (".claude",):
                        continue  # Skip hidden except .claude
                    stat = item.stat()
                    entries.append({
                        "name": item.name,
                        "path": str(item.relative_to(workspace)),
                        "type": "directory" if item.is_dir() else "file",
                        "size": stat.st_size if item.is_file() else 0,
                        "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                        "extension": item.suffix if item.is_file() else ""
                    })
            except PermissionError:
                self._send_json({"error": "Permission denied"}, 403)
                return
            self._send_json({
                "path": str(target.relative_to(workspace)) if target != workspace else "",
                "entries": entries,
                "parent": str(target.parent.relative_to(workspace)) if target != workspace else None
            })
            return

        # ─── File Content: read file for viewer ───
        if parsed.path == "/files/content":
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            params = parse_qs(parsed.query)
            rel_path = params.get("path", [""])[0]
            workspace = Path.home() / "savia"
            target = (workspace / rel_path).resolve()
            if not str(target).startswith(str(workspace)):
                self._send_json({"error": "Path traversal blocked"}, 403)
                return
            if not target.exists() or not target.is_file():
                self._send_json({"error": "File not found"}, 404)
                return
            # Limit file size to 500KB for mobile
            if target.stat().st_size > 512_000:
                self._send_json({"error": "File too large (max 500KB)", "size": target.stat().st_size}, 413)
                return
            # Determine if binary
            text_extensions = {".md", ".txt", ".py", ".kt", ".java", ".js", ".ts", ".tsx",
                             ".jsx", ".json", ".yaml", ".yml", ".xml", ".html", ".css",
                             ".sh", ".bash", ".toml", ".cfg", ".ini", ".gradle", ".sql",
                             ".rs", ".go", ".c", ".h", ".cpp", ".hpp", ".swift", ".rb",
                             ".bats", ".mermaid", ".svg", ".csv", ".env", ".properties"}
            if target.suffix.lower() not in text_extensions:
                self._send_json({"error": "Binary file — not viewable", "extension": target.suffix}, 415)
                return
            try:
                content = target.read_text(encoding="utf-8", errors="replace")
            except Exception as e:
                self._send_json({"error": f"Read error: {e}"}, 500)
                return
            self._send_json({
                "path": str(target.relative_to(workspace)),
                "name": target.name,
                "extension": target.suffix,
                "size": len(content),
                "lines": content.count("\n") + 1,
                "content": content
            })
            return

        self._send_json({"error": "Not found"}, 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        request_id = self._next_request_id()

        # --- POST /users (create user, admin only) ---
        if parsed.path == "/users":
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            if _get_user_role(self._auth_user) != "admin":
                self._send_json({"error": "Admin access required"}, 403)
                return
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode()
            try:
                data = json.loads(body)
                slug = data.get("slug", "").strip().lower().replace("@", "")
                if not slug:
                    self._send_json({"error": "slug is required"}, 400)
                    return
                if (USERS_DIR / slug).exists():
                    self._send_json({"error": f"User '{slug}' already exists"}, 409)
                    return
                token = _create_user(slug, data.get("name", ""), data.get("email", ""), data.get("role", "user"))
                log(f"User '{slug}' created by {self._auth_user or 'admin'}")
                self._send_json({"status": "created", "slug": slug, "token": token})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
            return

        # --- POST /users/{slug}/rotate-token ---
        if parsed.path.startswith("/users/") and parsed.path.endswith("/rotate-token"):
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            slug = parsed.path.split("/")[2]
            user_role = _get_user_role(self._auth_user)
            if user_role != "admin" and self._auth_user != slug:
                self._send_json({"error": "Can only rotate own token or be admin"}, 403)
                return
            new_token = _rotate_user_token(slug)
            if new_token:
                self._send_json({"status": "rotated", "slug": slug, "token": new_token})
            else:
                self._send_json({"error": f"User '{slug}' not found"}, 404)
            return

        # --- POST /users/{slug}/revoke (admin only) ---
        if parsed.path.startswith("/users/") and parsed.path.endswith("/revoke"):
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            if _get_user_role(self._auth_user) != "admin":
                self._send_json({"error": "Admin access required"}, 403)
                return
            slug = parsed.path.split("/")[2]
            if _revoke_user_token(slug):
                self._send_json({"status": "revoked", "slug": slug})
            else:
                self._send_json({"error": f"User '{slug}' not found"}, 404)
            return

        # --- POST /projects (create new project with scaffolding) ---
        if parsed.path == "/projects":
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode()
            try:
                data = json.loads(body)
                slug = data.get("slug", "").strip()
                if not slug:
                    self._send_json({"error": "slug is required"}, 400)
                    return
                workspace = Path(os.environ.get("SAVIA_WORKSPACE", Path.home() / "savia"))
                project_dir = workspace / "projects" / slug
                if project_dir.exists():
                    self._send_json({"error": f"Project '{slug}' already exists"}, 409)
                    return
                # Create scaffolding
                (project_dir / "backlog" / "pbi").mkdir(parents=True)
                (project_dir / "backlog" / "tasks").mkdir(parents=True)
                (project_dir / "specs").mkdir(parents=True)
                # _config.yaml
                (project_dir / "backlog" / "_config.yaml").write_text(
                    f'project: "{slug}"\npbi:\n  states: [New, Active, Resolved, Closed]\n'
                    f'  types: [User Story, Bug, Tech Debt, Spike]\n  id_prefix: "PBI"\n  id_counter: 1\n'
                    f'tasks:\n  states: [New, Active, In Review, Done, Blocked]\n  id_prefix: "TASK"\n')
                # CLAUDE.md
                pm_handle = data.get("pm", "")
                (project_dir / "CLAUDE.md").write_text(
                    f'# {data.get("name", slug)}\n\n'
                    f'> {data.get("description", "")}\n\n'
                    f'## Stack\n\n```\nFRAMEWORK = "{data.get("stack", "")}"\n```\n\n'
                    f'## Team\n\n| Role | Handle |\n|------|--------|\n| PM | {pm_handle} |\n')
                # equipo.md + reglas-negocio.md
                (project_dir / "equipo.md").write_text(f'# Team — {slug}\n\n| Handle | Role |\n|--------|------|\n| {pm_handle} | PM |\n')
                (project_dir / "reglas-negocio.md").write_text(f'# Business Rules — {slug}\n\n_Add rules here._\n')
                self._send_json({"status": "created", "slug": slug})
            except Exception as e:
                log(f"Create project error: {e}", "ERROR")
                self._send_json({"error": str(e)}, 500)
            return

        # --- POST /capture (no auth required) ---
        if parsed.path == "/capture":
            """POST /capture — Create a work item from captured content."""
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode()

            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                self._send_json({"error": "Invalid JSON"}, 400)
                return

            content = data.get("content", "").strip()
            item_type = data.get("type", "Task")  # PBI, Bug, Task
            project_id = data.get("projectId", "")

            if not content:
                self._send_json({"error": "Missing content"}, 400)
                return

            # Generate a mock ID
            import random
            mock_id = f"MOCK#{random.randint(900, 999)}"

            self._send_json({
                "id": mock_id,
                "status": "created",
                "type": item_type,
                "projectId": project_id,
                "createdAt": datetime.now().isoformat()
            })
            return

        if parsed.path == "/timelog":
            """POST /timelog — Log time against a task."""
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode()

            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                self._send_json({"error": "Invalid JSON"}, 400)
                return

            task_id = data.get("taskId", "")
            hours = data.get("hours", 0)
            date = data.get("date", "")

            if not task_id or not hours:
                self._send_json({"error": "Missing taskId or hours"}, 400)
                return

            self._send_json({
                "status": "logged",
                "taskId": task_id,
                "hours": hours,
                "date": date,
                "note": data.get("note")
            })
            return

        # --- POST /chat/permission — Permission response from mobile app ---
        if parsed.path == "/chat/permission":
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return

            content_length = int(self.headers.get("Content-Length", 0))
            if content_length > 10_000:
                self._send_json({"error": "Request body too large"}, 413)
                return
            body = self.rfile.read(content_length).decode()

            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                self._send_json({"error": "Invalid JSON"}, 400)
                return

            perm_session_id = data.get("session_id", "")
            perm_request_id = data.get("request_id", "")
            perm_behavior = data.get("behavior", "deny")

            if not perm_session_id or not perm_request_id:
                self._send_json({"error": "Missing session_id or request_id"}, 400)
                return

            if perm_behavior not in ("allow", "deny"):
                self._send_json({"error": "behavior must be 'allow' or 'deny'"}, 400)
                return

            # Convert non-UUID session IDs the same way as /chat does
            if not _is_valid_uuid(perm_session_id):
                if re.match(r'^[a-zA-Z0-9_-]{1,128}$', perm_session_id):
                    import uuid as _uuid_mod
                    perm_session_id = str(_uuid_mod.uuid5(_uuid_mod.NAMESPACE_DNS, f"savia.{perm_session_id}"))
                else:
                    self._send_json({"error": "Invalid session_id format"}, 400)
                    return

            log(f"[req:{request_id}] POST /chat/permission session={perm_session_id} behavior={perm_behavior}")

            with _interactive_sessions_lock:
                session = _interactive_sessions.get(perm_session_id)

            if not session:
                self._send_json({"error": "No active interactive session"}, 404)
                return

            if session.pending_request_id != perm_request_id:
                self._send_json({
                    "error": "request_id mismatch",
                    "expected": session.pending_request_id,
                    "received": perm_request_id
                }, 409)
                return

            session.resolve_permission(perm_request_id, perm_behavior)
            self._send_json({"status": "ok", "behavior": perm_behavior})
            return

        # --- POST /auth/register — Create per-user token (master token required) ---
        if parsed.path == "/auth/register":
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            if self._auth_user is not None:
                self._send_json({"error": "Only master token can register users"}, 403)
                return
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode()
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                self._send_json({"error": "Invalid JSON"}, 400)
                return
            username = data.get("username", "").strip()
            if not username or not re.match(r'^[a-zA-Z0-9_-]{1,64}$', username):
                self._send_json({"error": "Invalid username (alphanumeric, 1-64 chars)"}, 400)
                return
            user_token, user_dir = _get_or_create_user(username)
            log(f"[req:{request_id}] Registered user '{username}' -> {user_dir}")
            self._send_json({"user_token": user_token, "username": username})
            return

        if parsed.path != "/chat":
            self._send_json({"error": "Not found"}, 404)
            return

        if not self._check_auth():
            log(f"[req:{request_id}] Auth failed from {self.address_string()}", "WARN")
            self._send_json({"error": "Unauthorized"}, 401)
            return

        # A6 FIX: Read request body with size limit
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length > MAX_BODY_SIZE:
            self._send_json({"error": "Request body too large (max 1MB)"}, 413)
            return
        body = self.rfile.read(content_length).decode()

        log(f"[req:{request_id}] POST /chat from {self.address_string()} ({len(body)} bytes)")
        chat_log(f"[req:{request_id}] --- HTTP REQUEST ---")
        chat_log(f"[req:{request_id}] From: {self.address_string()}")
        chat_log(f"[req:{request_id}] Headers: Accept={self.headers.get('Accept','')}, Content-Type={self.headers.get('Content-Type','')}")
        chat_log(f"[req:{request_id}] Body: {body[:500]}")

        try:
            data = json.loads(body)
        except json.JSONDecodeError as e:
            log(f"[req:{request_id}] Invalid JSON: {e}", "ERROR")
            self._send_json({"error": "Invalid JSON"}, 400)
            return

        message = data.get("message", "").strip()
        if not message:
            log(f"[req:{request_id}] Empty message", "WARN")
            self._send_json({"error": "Empty message"}, 400)
            return

        session_id = data.get("session_id")
        interactive = data.get("interactive", False)  # Enable permission popups
        if interactive and not cli_adapter_supports_interactive():
            self._send_json({
                "error": "Interactive permission relay is unsupported for selected adapter",
                "status": "NOT_VERIFIED",
            }, 501)
            return

        # Build per-user system prompt with clear identity
        system_prompt = data.get("system_prompt")
        if not system_prompt:
            user_slug = self._auth_user
            user_profile = _get_user_profile(user_slug) if user_slug else None
            if user_profile:
                name = user_profile.get("name", user_slug)
                role = user_profile.get("role", "user")
                email = user_profile.get("email", "")
                system_prompt = (
                    "Eres Savia, la asistente de PM-Workspace. Inteligente, empática, concisa.\n\n"
                    f"USUARIO ACTUAL: {name} (@{user_slug})\n"
                    f"Rol: {role}\n"
                    f"Email: {email}\n\n"
                    f"IMPORTANTE: Conoces a este usuario. Su nombre es {name}. "
                    f"Cuando pregunte quién es, responde con su nombre y rol. "
                    f"Responde en español por defecto."
                )
            else:
                system_prompt = self.system_prompt

        # Claude CLI requires UUID session IDs — validate and convert non-UUID strings
        if session_id:
            if not _is_valid_uuid(session_id):
                # Validate format: UUID or alphanumeric only (no special chars)
                if not re.match(r'^[a-zA-Z0-9_-]{1,128}$', session_id):
                    log(f"[req:{request_id}] Rejected malformed session_id: {session_id}", "SECURITY")
                    self._send_json({"error": "Invalid session_id format"}, 400)
                    return
                import uuid as _uuid_mod
                original = session_id
                session_id = str(_uuid_mod.uuid5(_uuid_mod.NAMESPACE_DNS, f"savia.{session_id}"))
                log(f"[req:{request_id}] Converted session_id '{original}' -> {session_id}")

        # Per-user session ownership
        if self._auth_user and session_id:
            if _user_owns_session(self._auth_user, session_id):
                pass  # Already registered
            else:
                # New session for this user — register it
                _add_user_session(self._auth_user, session_id)

        mode_str = "interactive" if interactive else "one-shot"
        user_str = f", user={self._auth_user}" if self._auth_user else ""
        log(f"[req:{request_id}] Message='{message[:60]}', session={session_id}, mode={mode_str}{user_str}")

        # Periodic cleanup of stale interactive sessions
        _cleanup_stale_interactive_sessions()

        accept = self.headers.get("Accept", "")

        if "text/event-stream" in accept:
            # A2 FIX: Check SSE connection limit before opening stream
            if not _increment_sse_streams():
                log(f"[req:{request_id}] SSE connection limit ({MAX_CONCURRENT_STREAMS}) exceeded", "SECURITY")
                self._send_json({"error": "Too many concurrent SSE streams"}, 429)
                return

            # SSE streaming response
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self._send_cors_headers()
            self.end_headers()

            event_num = 0
            try:
                # Use one-shot streaming for reliability.
                # Interactive mode (stream-json stdin/stdout) can hang
                # when Claude CLI is slow to init or running nested.
                stream = stream_cli_response(message, session_id, system_prompt, request_id, self._auth_user)

                for chunk in stream:
                    event_data = json.dumps(chunk)
                    event_num += 1
                    chat_log(f"[req:{request_id}] SSE #{event_num}: {event_data[:300]}")
                    self.wfile.write(f"data: {event_data}\n\n".encode())
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError) as e:
                chat_log(f"[req:{request_id}] Client disconnected: {e}", "WARN")
            except Exception as e:
                chat_log(f"[req:{request_id}] SSE error: {traceback.format_exc()}", "ERROR")
            finally:
                # A2 FIX: Always decrement counter on stream end
                _decrement_sse_streams()

            log(f"[req:{request_id}] SSE complete ({event_num} events, mode={mode_str})")

        else:
            # Simple JSON response (collect all text)
            full_text = ""
            error = None

            for chunk in stream_cli_response(message, session_id, system_prompt, request_id, self._auth_user):
                if chunk["type"] == "text":
                    full_text += chunk["text"]
                elif chunk["type"] == "error":
                    error = chunk.get("text", "Unknown error")

            if error and not full_text:
                log(f"[req:{request_id}] Error response: {error[:100]}", "ERROR")
                self._send_json({"error": error}, 500)
            else:
                log(f"[req:{request_id}] OK response ({len(full_text)} chars)")
                self._send_json({
                    "response": full_text,
                    "session_id": session_id,
                    "timestamp": datetime.now().isoformat()
                })

    def do_DELETE(self):
        parsed = urlparse(self.path)

        # DELETE /users/{slug} (admin only)
        if parsed.path.startswith("/users/") and parsed.path.count("/") == 2:
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            if _get_user_role(self._auth_user) != "admin":
                self._send_json({"error": "Admin access required"}, 403)
                return
            slug = parsed.path.split("/")[2]
            user_dir = USERS_DIR / slug
            if not user_dir.exists():
                self._send_json({"error": f"User '{slug}' not found"}, 404)
                return
            import shutil as _shutil
            _shutil.rmtree(user_dir)
            with _user_token_cache_lock:
                _user_token_cache.pop(slug, None)
            log(f"User '{slug}' deleted by {self._auth_user or 'admin'}")
            self._send_json({"status": "deleted", "slug": slug})
            return

        if parsed.path == "/sessions":
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            if SESSIONS_DIR.exists():
                shutil.rmtree(SESSIONS_DIR)
                SESSIONS_DIR.mkdir(parents=True, exist_ok=True)
            self._send_json({"status": "cleared"})
            return

        self._send_json({"error": "Not found"}, 404)

    def do_PUT(self):
        """Handle PUT requests for updating configuration."""
        parsed = urlparse(self.path)

        # PUT /users/{slug} (admin only — update profile/role)
        if parsed.path.startswith("/users/") and parsed.path.count("/") == 2:
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            if _get_user_role(self._auth_user) != "admin":
                self._send_json({"error": "Admin access required"}, 403)
                return
            slug = parsed.path.split("/")[2]
            profile = _get_user_profile(slug)
            if not profile:
                self._send_json({"error": f"User '{slug}' not found"}, 404)
                return
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8")
            data = json.loads(body)
            # Prevent demoting last admin
            if profile.get("role") == "admin" and data.get("role") == "user":
                admins = [u for u in _list_all_users() if u["role"] == "admin"]
                if len(admins) <= 1:
                    self._send_json({"error": "Cannot demote the last admin"}, 400)
                    return
            for field in ["name", "email", "role"]:
                if field in data:
                    profile[field] = data[field]
            _save_user_profile(slug, profile)
            log(f"User '{slug}' updated by {self._auth_user or 'admin'}")
            self._send_json({"status": "updated", "slug": slug, "profile": profile})
            return

        if parsed.path == "/files/content":
            """PUT /files/content — Save file content (markdown editor)."""
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            try:
                content_length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(content_length).decode("utf-8")
                data = json.loads(body)
                rel_path = data.get("path", "")
                content = data.get("content", "")
                workspace = Path(os.environ.get("SAVIA_WORKSPACE", Path.home() / "savia"))
                target = (workspace / rel_path).resolve()
                if not str(target).startswith(str(workspace)):
                    self._send_json({"error": "Path traversal blocked"}, 403)
                    return
                target.write_text(content, encoding="utf-8")
                self._send_json({"status": "saved", "path": rel_path})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
            return

        if parsed.path == "/profile":
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            try:
                content_length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(content_length).decode("utf-8")
                data = json.loads(body)

                # Load existing profile
                profile_path = CONFIG_DIR / "profile.json"
                existing = {}
                if profile_path.exists():
                    try:
                        existing = json.loads(profile_path.read_text())
                    except Exception:
                        pass

                # Merge: update only provided fields
                for key in ("name", "email", "role", "language", "notes",
                            "work_hours_start", "work_hours_end", "lunch_break",
                            "break_strategy", "detail_level", "alert_style",
                            "output_mode", "theme", "accessibility"):
                    if key in data:
                        existing[key] = data[key]

                # Save
                profile_path.parent.mkdir(parents=True, exist_ok=True)
                profile_path.write_text(json.dumps(existing, indent=2, ensure_ascii=False))

                log(f"Profile updated: {list(data.keys())}")
                self._send_json({"status": "updated", "profile": existing})
            except json.JSONDecodeError:
                self._send_json({"error": "Invalid JSON"}, 400)
            except Exception as e:
                log(f"Error updating profile: {e}", "ERROR")
                self._send_json({"error": str(e)}, 500)
            return

        if parsed.path == "/git-config":
            """PUT /git-config — Update git global configuration (requires auth)."""
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            try:
                content_length = int(self.headers.get("Content-Length", 0))
                if content_length > MAX_BODY_SIZE:
                    self._send_json({"error": "Request body too large"}, 413)
                    return
                body = self.rfile.read(content_length).decode("utf-8")
                data = json.loads(body)
                updated = []

                # C3 FIX: Input validation — prevent command injection via git config values
                import re
                _SAFE_GIT_VALUE = re.compile(r'^[a-zA-Z0-9 ._@+\-áéíóúñÁÉÍÓÚÑüÜ()]{1,200}$')
                _SAFE_EMAIL = re.compile(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$')
                _SAFE_CREDENTIAL = re.compile(r'^[a-zA-Z0-9._/\-]{1,100}$')

                if "name" in data:
                    if not _SAFE_GIT_VALUE.match(data["name"]):
                        self._send_json({"error": "Invalid name: only alphanumeric, spaces, dots, hyphens allowed"}, 400)
                        return
                    subprocess.run(['git', 'config', '--global', 'user.name', data["name"]],
                                   check=True, capture_output=True, timeout=5)
                    updated.append("name")

                if "email" in data:
                    if not _SAFE_EMAIL.match(data["email"]):
                        self._send_json({"error": "Invalid email format"}, 400)
                        return
                    subprocess.run(['git', 'config', '--global', 'user.email', data["email"]],
                                   check=True, capture_output=True, timeout=5)
                    updated.append("email")

                if "credential_helper" in data:
                    val = data["credential_helper"]
                    if val:
                        if not _SAFE_CREDENTIAL.match(val):
                            self._send_json({"error": "Invalid credential helper: only alphanumeric, dots, slashes, hyphens allowed"}, 400)
                            return
                        subprocess.run(['git', 'config', '--global', 'credential.helper', val],
                                       check=True, capture_output=True, timeout=5)
                    else:
                        subprocess.run(['git', 'config', '--global', '--unset', 'credential.helper'],
                                       capture_output=True, timeout=5)
                    updated.append("credential_helper")

                # C4 FIX: PAT stored with Fernet encryption (or env var fallback)
                if "pat" in data:
                    pat_path = CONFIG_DIR / "github_pat.enc"
                    try:
                        from cryptography.fernet import Fernet
                        key_path = CONFIG_DIR / ".pat_key"
                        if not key_path.exists():
                            key = Fernet.generate_key()
                            key_path.write_bytes(key)
                            key_path.chmod(0o600)
                        else:
                            key = key_path.read_bytes()
                        f = Fernet(key)
                        encrypted = f.encrypt(data["pat"].encode())
                        pat_path.write_bytes(encrypted)
                    except ImportError:
                        # Fallback: base64 if cryptography not installed
                        import base64
                        encoded = base64.b64encode(data["pat"].encode()).decode()
                        pat_path.write_text(encoded)
                        log("WARNING: cryptography package not installed, PAT stored with base64 only", "WARN")
                    pat_path.chmod(0o600)
                    updated.append("pat")
                    log("GitHub PAT updated (stored securely)")

                log(f"Git config updated: {updated}")
                self._send_json({"status": "updated", "fields": updated})
            except json.JSONDecodeError:
                self._send_json({"error": "Invalid JSON"}, 400)
            except subprocess.CalledProcessError as e:
                self._send_json({"error": f"Git config error: {e.stderr}"}, 500)
            except Exception as e:
                log(f"Error updating git config: {e}", "ERROR")
                self._send_json({"error": str(e)}, 500)
            return

        if parsed.path == "/team":
            """PUT /team — Update team member profiles (requires auth)."""
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            try:
                content_length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(content_length).decode("utf-8")
                data = json.loads(body)

                team_dir = Path.home() / "savia" / ".claude" / "profiles" / "users"
                team_dir.mkdir(parents=True, exist_ok=True)

                action = data.get("action", "update")  # update, add, remove

                if action == "add":
                    slug = data.get("slug", "").strip().lower().replace(" ", "-")
                    if not slug:
                        self._send_json({"error": "slug is required"}, 400)
                        return
                    member_dir = team_dir / slug
                    member_dir.mkdir(parents=True, exist_ok=True)
                    # Create identity.md with frontmatter
                    identity = data.get("identity", {})
                    fm_lines = ["---"]
                    for k, v in identity.items():
                        fm_lines.append(f"{k}: {v}")
                    fm_lines.append("---")
                    fm_lines.append(f"\n# {identity.get('name', slug)}\n")
                    (member_dir / "identity.md").write_text("\n".join(fm_lines))
                    log(f"Team member added: {slug}")
                    self._send_json({"status": "added", "slug": slug})

                elif action == "remove":
                    slug = data.get("slug", "").strip()
                    if not slug:
                        self._send_json({"error": "slug is required"}, 400)
                        return
                    member_dir = team_dir / slug
                    if member_dir.exists():
                        shutil.rmtree(member_dir)
                        log(f"Team member removed: {slug}")
                        self._send_json({"status": "removed", "slug": slug})
                    else:
                        self._send_json({"error": f"Member '{slug}' not found"}, 404)

                elif action == "update":
                    slug = data.get("slug", "").strip()
                    if not slug:
                        self._send_json({"error": "slug is required"}, 400)
                        return
                    member_dir = team_dir / slug
                    if not member_dir.exists():
                        self._send_json({"error": f"Member '{slug}' not found"}, 404)
                        return
                    identity = data.get("identity", {})
                    if identity:
                        # Merge with existing identity.md
                        existing_data = {}
                        identity_file = member_dir / "identity.md"
                        if identity_file.exists():
                            content = identity_file.read_text()
                            if content.startswith("---"):
                                parts = content.split("---", 2)
                                if len(parts) >= 3:
                                    for line in parts[1].strip().split('\n'):
                                        if ':' in line:
                                            key, val = line.split(':', 1)
                                            existing_data[key.strip()] = val.strip()
                        existing_data.update(identity)
                        fm_lines = ["---"]
                        for k, v in existing_data.items():
                            fm_lines.append(f"{k}: {v}")
                        fm_lines.append("---")
                        fm_lines.append(f"\n# {existing_data.get('name', slug)}\n")
                        identity_file.write_text("\n".join(fm_lines))
                    log(f"Team member updated: {slug}")
                    self._send_json({"status": "updated", "slug": slug})
                else:
                    self._send_json({"error": f"Unknown action: {action}"}, 400)

            except json.JSONDecodeError:
                self._send_json({"error": "Invalid JSON"}, 400)
            except Exception as e:
                log(f"Error updating team: {e}", "ERROR")
                self._send_json({"error": str(e)}, 500)
            return

        if parsed.path == "/company":
            """PUT /company — Update company profile sections (requires auth)."""
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            try:
                content_length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(content_length).decode("utf-8")
                data = json.loads(body)

                company_dir = Path.home() / "savia" / ".claude" / "profiles" / "company"
                company_dir.mkdir(parents=True, exist_ok=True)

                section = data.get("section", "").strip()
                valid_sections = ["identity", "structure", "strategy", "policies", "technology", "vertical"]
                if section not in valid_sections:
                    self._send_json({"error": f"Invalid section. Must be one of: {valid_sections}"}, 400)
                    return

                fields = data.get("fields", {})
                content_text = data.get("content", "")

                # Build markdown with YAML frontmatter
                section_file = company_dir / f"{section}.md"

                # Merge with existing if present
                existing_fields = {}
                existing_content = ""
                if section_file.exists():
                    raw = section_file.read_text()
                    if raw.startswith("---"):
                        parts = raw.split("---", 2)
                        if len(parts) >= 3:
                            for line in parts[1].strip().split('\n'):
                                if ':' in line:
                                    key, val = line.split(':', 1)
                                    existing_fields[key.strip()] = val.strip()
                            existing_content = parts[2].strip()

                existing_fields.update(fields)
                if content_text:
                    existing_content = content_text

                fm_lines = ["---"]
                for k, v in existing_fields.items():
                    fm_lines.append(f"{k}: {v}")
                fm_lines.append("---")
                if existing_content:
                    fm_lines.append(f"\n{existing_content}")

                section_file.write_text("\n".join(fm_lines))
                log(f"Company section updated: {section}")
                self._send_json({"status": "updated", "section": section})

            except json.JSONDecodeError:
                self._send_json({"error": "Invalid JSON"}, 400)
            except Exception as e:
                log(f"Error updating company: {e}", "ERROR")
                self._send_json({"error": str(e)}, 500)
            return

        self._send_json({"error": "Not found"}, 404)

# --- HTTP Install Server (plain HTTP, no auth) ---

class InstallHandler(http.server.BaseHTTPRequestHandler):
    """Lightweight HTTP handler that serves only the install page and APK download."""

    def log_message(self, format, *args):
        log(f"[install] {self.address_string()} - {format % args}", "HTTP")

    def _send_json(self, data: dict, status: int = 200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path in ("/", "/install"):
            html = _build_install_html(_find_apk())
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(html.encode())
            return

        if parsed.path == "/download/apk":
            apk = _find_apk()
            if not apk:
                self.send_response(404)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.end_headers()
                self.wfile.write(b"<h1>No APK available</h1>")
                return
            log(f"[install] APK download: {apk.name} to {self.address_string()}")
            self.send_response(200)
            self.send_header("Content-Type", "application/vnd.android.package-archive")
            self.send_header("Content-Disposition", f'attachment; filename="{apk.name}"')
            self.send_header("Content-Length", str(apk.stat().st_size))
            self.end_headers()
            with open(apk, "rb") as f:
                shutil.copyfileobj(f, self.wfile)
            return

        # --- Auto-Update Endpoints ---
        if parsed.path == "/update/check":
            apk = _find_apk()
            if not apk:
                self._send_json({"error": "No APK available"}, 404)
                return
            info = _get_apk_info(apk)
            self._send_json(info)
            return

        if parsed.path == "/update/download":
            apk = _find_apk()
            if not apk:
                self._send_json({"error": "No APK available"}, 404)
                return
            log(f"[install] APK download via /update: {apk.name} to {self.address_string()}")
            self.send_response(200)
            self.send_header("Content-Type", "application/vnd.android.package-archive")
            self.send_header("Content-Disposition", f'attachment; filename="{apk.name}"')
            self.send_header("Content-Length", str(apk.stat().st_size))
            self.end_headers()
            with open(apk, "rb") as f:
                shutil.copyfileobj(f, self.wfile)
            return

        # OpenAPI specification
        if parsed.path == "/openapi.json":
            spec_path = Path(__file__).resolve().parent / "openapi.yaml"
            if not spec_path.exists():
                self._send_json({"error": "OpenAPI spec not found"}, 404)
                return
            content = spec_path.read_text()
            self.send_response(200)
            self.send_header("Content-Type", "application/x-yaml")
            self.end_headers()
            self.wfile.write(content.encode())
            return

        # Redirect everything else to /install
        self.send_response(302)
        self.send_header("Location", "/install")
        self.end_headers()


# --- Main ---

def build_argument_parser() -> argparse.ArgumentParser:
    """Build the stable bridge CLI, including explicit provider selection."""
    parser = argparse.ArgumentParser(
        description=f"Savia Bridge v{BRIDGE_VERSION} — CLI-managed AI bridge"
    )
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"Port (default: {DEFAULT_PORT})")
    parser.add_argument("--host", type=str, default=DEFAULT_HOST, help=f"Host (default: {DEFAULT_HOST})")
    parser.add_argument("--auth-token", type=str, help="Auth token (auto-generated if not set)")
    parser.add_argument("--no-auth", action="store_true", help="Disable authentication (not recommended)")
    parser.add_argument("--no-tls", action="store_true", help="Disable TLS (not recommended)")
    parser.add_argument("--system-prompt", type=str, help="Default system prompt")
    parser.add_argument("--cli-adapter", choices=("claude", "codex", "opencode"),
                        default="claude", help="CLI adapter (default: claude)")
    parser.add_argument("--print-token", action="store_true", help="Print the auth token and exit")
    parser.add_argument("--print-fingerprint", action="store_true", help="Print the TLS cert fingerprint and exit")
    parser.add_argument("--install-port", type=int, default=DEFAULT_INSTALL_PORT, help=f"HTTP port for install page (default: {DEFAULT_INSTALL_PORT})")
    parser.add_argument("--no-install-server", action="store_true", help="Disable the HTTP install server")
    return parser


def main():
    """
    Main entry point for Savia Bridge server.

    Parses command-line arguments, initializes configuration (auth token, TLS),
    verifies Claude Code CLI installation, and starts the HTTPS server.

    Command-line Arguments:
        --port PORT              HTTPS port (default: 8922)
        --host HOST              Bind address (default: 0.0.0.0)
        --auth-token TOKEN       Bearer token (auto-generated if not provided)
        --no-auth                Disable authentication (not recommended)
        --no-tls                 Run over HTTP instead of HTTPS (not recommended)
        --system-prompt PROMPT   Default system prompt for messages
        --cli-adapter NAME       Explicit CLI adapter; default: claude
        --print-token            Print auth token to stdout and exit
        --print-fingerprint      Print TLS cert SHA-256 fingerprint and exit
        --install-port PORT      HTTP port for /install page (default: 8080)
        --no-install-server      Don't run the HTTP install server

    Initialization Steps:
        1. Parse arguments
        2. Create configuration directories (~/.savia/bridge/, sessions/)
        3. Generate or load auth token (unless --no-auth)
        4. Generate or load TLS certificate and key (unless --no-tls)
        5. Verify only the selected CLI adapter
        6. Load user profile from ~/.savia/bridge/profile.json
        7. Start HTTPS server on specified port and host
        8. (Optionally) Start HTTP install server on port 8080
        9. Block and serve requests until interrupted

    Configuration Files Created (if not present):
        ~/.savia/bridge/auth_token          Auto-generated 43-char token
        ~/.savia/bridge/cert.pem            Self-signed TLS certificate
        ~/.savia/bridge/key.pem             TLS private key
        ~/.savia/bridge/cert_fingerprint.txt SHA-256 fingerprint
        ~/.savia/bridge/profile.json        User profile (name, email, role)
        ~/.savia/bridge/sessions/           Multi-turn session storage

    Logging:
        All operations logged to ~/.savia/bridge/bridge.log

    Exit Codes:
        0: Normal exit (server stopped)
        1: Error (missing/unverified adapter, TLS error, port in use, etc.)

    Example Usage:
        python3 savia-bridge.py                              # Default: HTTPS on 0.0.0.0:8922
        python3 savia-bridge.py --port 9000                  # Custom HTTPS port
        python3 savia-bridge.py --print-token                # Get auth token
        python3 savia-bridge.py --no-auth --no-tls          # HTTP without auth (dev only)
    """
    args = build_argument_parser().parse_args()

    # Setup directories
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    SESSIONS_DIR.mkdir(parents=True, exist_ok=True)

    # Setup auth
    if args.no_auth:
        token = None
        log("WARNING: Authentication disabled")
    elif args.auth_token:
        token = args.auth_token
    else:
        token = get_or_create_token()

    # Migrate existing profiles and load per-user token cache
    _migrate_existing_profiles()
    _init_user_token_cache()

    if args.print_token:
        print(token or "(no auth)")
        sys.exit(0)

    # Setup TLS
    use_tls = not args.no_tls
    cert_fingerprint = None
    if use_tls:
        try:
            cert_path, key_path, cert_fingerprint = get_or_create_tls_cert()
        except FileNotFoundError:
            log("Could not generate TLS certificate. Running without TLS.", "WARN")
            use_tls = False

    if args.print_fingerprint:
        if cert_fingerprint:
            print(cert_fingerprint)
        else:
            print("(no TLS)")
        sys.exit(0)

    # Verify only the explicitly selected CLI adapter.
    try:
        adapter_status = configure_cli_adapter(args.cli_adapter)
        log(f"CLI adapter available: {args.cli_adapter} ({adapter_status['status']})")
    except (FileNotFoundError, RuntimeError) as e:
        log(str(e), "ERROR")
        sys.exit(1)

    # Load user profile
    user_profile = _load_user_profile()

    # Configure handler
    SaviaBridgeHandler.auth_token = token
    SaviaBridgeHandler.system_prompt = args.system_prompt or (
        "Eres Savia, una asistente de gestión de proyectos inteligente, empática y eficiente. "
        "Respondes en el idioma del usuario (español por defecto). "
        "Eres concisa pero cercana. Usas datos cuando los tienes disponibles.\n\n"
        f"Contexto del usuario:\n{user_profile}"
    )

    # Start server
    # ThreadingHTTPServer: each request runs in its own thread so /chat (which
    # blocks while the selected CLI streams) never prevents /health, /dashboard, etc.
    server = http.server.ThreadingHTTPServer((args.host, args.port), SaviaBridgeHandler)

    protocol = "HTTP"
    if use_tls:
        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        # M3 FIX: Set minimum TLS version to 1.2 and restrict cipher suite
        ssl_context.minimum_version = ssl.TLSVersion.TLSv1_2
        ssl_context.set_ciphers('ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:ECDHE+AES256:AES256:!aNULL:!eNULL:!MD5:!DSS')
        ssl_context.load_cert_chain(cert_path, key_path)
        server.socket = ssl_context.wrap_socket(server.socket, server_side=True)
        protocol = "HTTPS"

    log(f"Savia Bridge v{BRIDGE_VERSION} starting on {protocol.lower()}://{args.host}:{args.port}")
    if use_tls:
        log(f"TLS: ENABLED")
        log(f"Certificate fingerprint: {cert_fingerprint}")
    else:
        log(f"TLS: DISABLED", "WARN")
    if token:
        log(f"Auth token: {token}")
        log(f"Token stored in: {TOKEN_FILE}")
    log(f"")
    log(f"Log files:")
    log(f"  Server:  {LOG_FILE}")
    log(f"  Chat:    {CHAT_LOG_FILE}")
    log(f"")
    log(f"--- Mobile app config ---")
    log(f"  Protocol: {protocol}")
    log(f"  Host: <your-vpn-ip>")
    log(f"  Port: {args.port}")
    log(f"  Token: {token or '(none)'}")
    if cert_fingerprint:
        log(f"  Fingerprint: {cert_fingerprint}")
    log(f"-------------------------")
    log(f"")
    log(f"--- APK Install ---")
    apk = _find_apk()
    if apk:
        log(f"  APK: {apk.name} ({apk.stat().st_size / 1024 / 1024:.1f} MB)")
    else:
        log(f"  No APK found. Place .apk in: {APK_DIR}")
    log(f"-------------------")

    # Start HTTP install server (plain HTTP, no auth, separate port)
    install_server = None
    if not args.no_install_server:
        try:
            install_server = http.server.ThreadingHTTPServer((args.host, args.install_port), InstallHandler)
            install_thread = threading.Thread(target=install_server.serve_forever, daemon=True)
            install_thread.start()
            log(f"")
            log(f"--- APK Install Server ---")
            log(f"  HTTP (no TLS) on port {args.install_port}")
            log(f"  Open in browser: http://<your-ip>:{args.install_port}")
            if apk:
                log(f"  APK ready: {apk.name}")
            log(f"--------------------------")
        except OSError as e:
            log(f"Could not start install server on port {args.install_port}: {e}", "WARN")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("Shutting down...")
        server.shutdown()
        if install_server:
            install_server.shutdown()

if __name__ == "__main__":
    main()
