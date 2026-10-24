"""SPEC-T03: Teams attachments detection + download pipeline.

Scans extracted Teams chat JSONs for attachment metadata, extracts URLs where
present, dispatches to digest manifests. Download of binary uses daemon's
Playwright context via CDP fetch evaluation.
"""
import argparse
import hashlib
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path


SUPPORTED_EXTS = {
    ".xlsx": "excel", ".xls": "excel", ".csv": "excel",
    ".pdf": "pdf",
    ".docx": "word", ".doc": "word",
    ".pptx": "pptx", ".ppt": "pptx",
    ".txt": "text", ".md": "text",
    ".png": "image", ".jpg": "image", ".jpeg": "image",
    ".zip": "archive",
}


def slugify(s):
    s = s.lower().strip()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"-+", "-", s).strip("-")
    return s[:80]


def sha256_of(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def extract_attachments_from_chat(chat_json):
    """Scan messages for attachment-like patterns (filenames, sharepoint URLs)."""
    found = []
    msgs = (chat_json.get("active") or {}).get("messages") or []
    # SharePoint file URL patterns
    sp_url_re = re.compile(r"https?://[a-z0-9\-]+\.sharepoint\.com/[^\s'\"]+\.(?:xlsx|xls|csv|pdf|docx|doc|pptx|ppt|txt|zip|png|jpg|jpeg)",
                           re.IGNORECASE)
    # filename with extension
    filename_re = re.compile(r"\b([A-Za-z0-9_\-][A-Za-z0-9_\-\.\(\) ]{0,120}\.(?:xlsx|xls|csv|pdf|docx|doc|pptx|ppt|txt|zip|png|jpg|jpeg))\b",
                             re.IGNORECASE)
    for m in msgs:
        content = m.get("content") or ""
        author = m.get("author") or "?"
        ts = m.get("time") or "?"
        # URLs
        for url_match in sp_url_re.finditer(content):
            url = url_match.group(0)
            ext = ("." + url.rsplit(".", 1)[-1]).lower()
            if ext not in SUPPORTED_EXTS:
                continue
            found.append({
                "kind": "sharepoint_url",
                "url": url,
                "ext": ext,
                "digest_type": SUPPORTED_EXTS[ext],
                "author": author,
                "time": ts,
            })
        # Filenames without URL — possible attachment name in UI
        for fn_match in filename_re.finditer(content):
            name = fn_match.group(1).strip()
            ext = Path(name).suffix.lower()
            if ext not in SUPPORTED_EXTS:
                continue
            # Skip if already captured as URL component
            if any(a.get("kind") == "sharepoint_url" and name in a.get("url","") for a in found):
                continue
            found.append({
                "kind": "filename_mention",
                "filename": name,
                "ext": ext,
                "digest_type": SUPPORTED_EXTS[ext],
                "author": author,
                "time": ts,
            })
    return found


def scan_chat_dirs(roots):
    """Yield (chat_file, chat_json) for all chat-*.json under given roots."""
    for root in roots:
        root_p = Path(root)
        if not root_p.exists():
            continue
        for f in root_p.rglob("*.json"):
            if not (f.name.startswith("chat-") or f.name.startswith("mensaje-")):
                continue
            try:
                d = json.loads(f.read_text(encoding="utf-8"))
                yield f, d
            except Exception:
                continue


def write_manifest(attachment, source_chat, manifest_dir):
    """Write manifest for attachment download dispatch."""
    manifest_dir.mkdir(parents=True, exist_ok=True)
    # Key for idempotency: sha256 of (url or filename) + chat
    key_input = (attachment.get("url") or attachment.get("filename") or "") + "|" + source_chat
    key = sha256_of(key_input)
    mf_path = manifest_dir / (key[:40] + ".manifest.json")
    if mf_path.exists():
        return None
    manifest = {
        "source": "teams",
        "source_chat": source_chat,
        "detected_at": datetime.now().isoformat(),
        "attachment": attachment,
        "key": key,
    }
    mf_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return mf_path


# Sovereign clouds included: gov./dod.teams.microsoft.us match by suffix.
_AUTH_PAGE_HOSTS = ("teams.microsoft.com", "teams.cloud.microsoft", "teams.live.com",
                    "teams.microsoft.us")
_SHAREPOINT_SUFFIXES = (".sharepoint.com", ".sharepoint.us", ".sharepoint.cn")


def is_authenticated_page_url(url):
    """True when the URL's host is SharePoint or Teams (not a substring match).

    The fetch runs inside the chosen page, so a tab such as
    https://evil.example/?u=sharepoint.com must never be selected.
    """
    parsed = urllib.parse.urlsplit(url or "")
    host = (parsed.hostname or "").lower()
    if parsed.scheme != "https":
        return False
    return host.endswith(_SHAREPOINT_SUFFIXES) or any(
        host == h or host.endswith("." + h) for h in _AUTH_PAGE_HOSTS)


def pick_authenticated_page(targets):
    for t in targets:
        if t.get("type") == "page" and is_authenticated_page_url(t.get("url")):
            return t
    return None


def download_via_daemon(url, dest_path, cdp_port):
    """Download a URL using the daemon's authenticated context via CDP fetch."""
    import websocket
    cdp_url = "http://127.0.0.1:" + str(cdp_port)
    try:
        with urllib.request.urlopen(cdp_url + "/json", timeout=5) as r:
            targets = json.loads(r.read())
    except Exception as err:
        return {"ok": False, "error": "cdp not available: " + str(err)[:100]}
    page = pick_authenticated_page(targets)
    if not page:
        return {"ok": False, "error": "no authenticated page"}
    ws_url = page["webSocketDebuggerUrl"]
    try:
        ws = websocket.create_connection(ws_url, timeout=30, suppress_origin=True)
    except Exception as err:
        return {"ok": False, "error": "ws: " + str(err)[:100]}
    try:
        js = """
        (async () => {
            try {
                const r = await fetch('URL', {credentials: 'include'});
                if (!r.ok) return {ok: false, status: r.status};
                const buf = await r.arrayBuffer();
                const bytes = new Uint8Array(buf);
                const CHUNK = 8192;
                let binary = '';
                for (let i = 0; i < bytes.length; i += CHUNK) {
                    binary += String.fromCharCode.apply(null, bytes.slice(i, i + CHUNK));
                }
                return {ok: true, status: r.status, b64: btoa(binary), size: bytes.length};
            } catch (e) { return {ok: false, err: String(e).slice(0, 200)}; }
        })()
        """.replace("URL", url.replace("'", "\\'"))
        req = {"id": int(time.time() * 1000) % 1000000, "method": "Runtime.evaluate",
               "params": {"expression": js, "returnByValue": True, "awaitPromise": True}}
        ws.send(json.dumps(req))
        deadline = time.time() + 120
        result = None
        while time.time() < deadline:
            msg = json.loads(ws.recv())
            if msg.get("id") == req["id"]:
                result = msg.get("result", {})
                break
        if not result:
            return {"ok": False, "error": "timeout"}
        val = (result.get("result") or {}).get("value") or {}
        if not val.get("ok"):
            return {"ok": False, "error": "fetch failed: " + json.dumps(val)[:200]}
        import base64
        data = base64.b64decode(val.get("b64", ""))
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        dest_path.write_bytes(data)
        return {"ok": True, "size": len(data), "path": str(dest_path)}
    finally:
        ws.close()


def main():
    ap = argparse.ArgumentParser(description="Teams attachments pipeline (SPEC-T03)")
    ap.add_argument("--roots", nargs="+",
                    default=[
                        str(Path.home() / ".savia" / "teams-parallel-output" / "account1"),
                        str(Path.home() / ".savia" / "teams-parallel-output" / "account2"),
                    ])
    ap.add_argument("--manifest-dir", default=str(Path.home() / ".savia" / "teams-attachments-manifests"))
    ap.add_argument("--download-dir", default=str(Path.home() / ".savia" / "teams-attachments"))
    ap.add_argument("--download", action="store_true", help="Actually download binaries (needs daemon up)")
    ap.add_argument("--cdp-port", type=int, default=None, help="Override daemon CDP port")
    ap.add_argument("--account", default="account1")
    ap.add_argument("--max-downloads", type=int, default=10)
    args = ap.parse_args()

    manifest_dir = Path(args.manifest_dir)
    download_dir = Path(args.download_dir)
    manifest_dir.mkdir(parents=True, exist_ok=True)
    download_dir.mkdir(parents=True, exist_ok=True)

    # Detection phase
    total = 0
    detected = 0
    dispatched = 0
    skipped = 0
    detections_by_chat = {}
    for chat_file, chat_json in scan_chat_dirs(args.roots):
        total += 1
        attachments = extract_attachments_from_chat(chat_json)
        if not attachments:
            continue
        detections_by_chat[chat_file.name] = attachments
        for att in attachments:
            detected += 1
            mf = write_manifest(att, chat_file.name, manifest_dir)
            if mf:
                dispatched += 1
            else:
                skipped += 1

    print("[t03] scanned chats=" + str(total) + " detected_attachments=" + str(detected)
          + " new_manifests=" + str(dispatched) + " already_seen=" + str(skipped), file=sys.stderr)

    # Download phase (optional)
    if args.download:
        cdp_port = args.cdp_port or (9222 if args.account == "account1" else 9223)
        downloaded = 0
        failed = 0
        for mf_path in sorted(manifest_dir.glob("*.manifest.json"))[:args.max_downloads]:
            try:
                mf = json.loads(mf_path.read_text(encoding="utf-8"))
            except Exception:
                continue
            att = mf.get("attachment", {})
            if att.get("kind") != "sharepoint_url":
                continue  # Only URL attachments can be downloaded
            url = att.get("url", "")
            if not url:
                continue
            # Check if already downloaded
            if mf.get("downloaded"):
                continue
            name = Path(urllib.parse.urlparse(url).path).name or "download.bin"
            dest = download_dir / (mf_path.stem + "_" + slugify(name))
            print("[t03] downloading " + name[:60] + " -> " + dest.name[:60], file=sys.stderr)
            res = download_via_daemon(url, dest, cdp_port)
            mf["download_attempt"] = datetime.now().isoformat()
            if res.get("ok"):
                mf["downloaded"] = True
                mf["download_path"] = str(dest)
                mf["download_size"] = res.get("size")
                downloaded += 1
            else:
                mf["download_error"] = res.get("error", "?")[:200]
                failed += 1
            mf_path.write_text(json.dumps(mf, ensure_ascii=False, indent=2), encoding="utf-8")
        print("[t03] downloaded=" + str(downloaded) + " failed=" + str(failed), file=sys.stderr)


if __name__ == "__main__":
    main()
