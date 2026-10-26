"""sp-recordings.py — list/download Teams meeting recordings + VTTs from
personal OneDrive of a configured account.

Tenant-agnostic. Per-account differences (sharepoint_url, personal_user,
drive_id, recordings_path) live in ~/.savia/mail-accounts.json.
"""
import argparse, json, os, sys, time, urllib.request, urllib.parse
from datetime import datetime, timedelta, timezone
from pathlib import Path
import websocket


def load_account(account):
    cfg = json.load(open(Path.home() / ".savia" / "mail-accounts.json", encoding="utf-8"))
    if account not in cfg:
        sys.stderr.write("unknown account: " + account + "\n"); sys.exit(2)
    d = cfg[account]
    required = ["sharepoint_url", "personal_user", "drive_id", "recordings_path"]
    missing = [k for k in required if not d.get(k)]
    if missing:
        sys.stderr.write("account " + account + " missing fields: " + str(missing) + "\n"); sys.exit(2)
    return d


def cdp_send(ws, mid, method, params=None, timeout=60):
    ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    deadline = time.time() + timeout
    while time.time() < deadline:
        m = json.loads(ws.recv())
        if m.get("id") == mid:
            if "error" in m:
                raise RuntimeError("CDP: " + json.dumps(m["error"]))
            return m.get("result", {})
    raise TimeoutError("CDP timeout " + method)


def is_sharepoint_url(url):
    """True only when the URL's host is *.sharepoint.com (not a substring match).

    The page's window.location.origin receives user and drive ids, so a tab
    like https://evil.example/?next=sharepoint.com must never be selected.
    """
    parsed = urllib.parse.urlsplit(url or "")
    host = (parsed.hostname or "").lower()
    return parsed.scheme == "https" and host.endswith(".sharepoint.com")


def find_sp_page(cdp_url):
    targets = json.loads(urllib.request.urlopen(cdp_url + "/json", timeout=5).read())
    for t in targets:
        if t.get("type") == "page" and is_sharepoint_url(t.get("url")):
            return t
    return None


def eval_in(ws, expr, timeout=60):
    r = cdp_send(ws, int(time.time()*1000) % 99999999, "Runtime.evaluate",
                 {"expression": expr, "returnByValue": True, "awaitPromise": True}, timeout=timeout)
    return (r.get("result") or {}).get("value")


def list_recordings(ws, user, drive_id, folder):
    folder_q = urllib.parse.quote(folder)
    js = """(async()=>{
        const o = window.location.origin;
        const url = o + '/personal/__USER__/_api/v2.1/drives/__DRIVE__/root:/__FOLDER__:/children?$top=500';
        const r = await fetch(url, {credentials:'include', headers:{'Accept':'application/json'}});
        if (!r.ok) return {status: r.status, text: (await r.text()).slice(0, 300)};
        const j = await r.json();
        return {status: 200, items: (j.value || []).map(x => ({
            id: x.id, name: x.name, size: x.size,
            mtime: x.lastModifiedDateTime,
            mime: x.file && x.file.mimeType,
            webUrl: x.webUrl
        }))};
    })()"""
    js = js.replace("__USER__", user).replace("__DRIVE__", drive_id).replace("__FOLDER__", folder_q)
    return eval_in(ws, js, timeout=60)


def fetch_transcript(ws, user, drive_id, item_id):
    js = """(async()=>{
        const o = window.location.origin;
        const list = await fetch(o + '/personal/__USER__/_api/v2.1/drives/__DRIVE__/items/__ITEM__/media/transcripts',
            {credentials:'include', headers:{'Accept':'application/json'}});
        if (!list.ok) return {status: list.status, text: (await list.text()).slice(0, 300)};
        const j = await list.json();
        const tr = (j.value || [])[0];
        if (!tr) return {status: 204, msg: 'no transcript track'};
        const trId = tr.id;
        const cont = await fetch(o + '/personal/__USER__/_api/v2.1/drives/__DRIVE__/items/__ITEM__/media/transcripts/' + trId + '/content',
            {credentials:'include', headers:{'Accept':'text/vtt'}});
        if (!cont.ok) return {status: cont.status, text: (await cont.text()).slice(0, 300)};
        const vtt = await cont.text();
        return {status: 200, vtt: vtt, lang: tr.transcriptLanguage};
    })()"""
    js = js.replace("__USER__", user).replace("__DRIVE__", drive_id).replace("__ITEM__", item_id)
    return eval_in(ws, js, timeout=120)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--account", required=True)
    ap.add_argument("--action", choices=["list", "download-transcripts"], default="list")
    ap.add_argument("--since-days", type=int, default=14)
    ap.add_argument("--max", type=int, default=20)
    ap.add_argument("--out-dir", default=None)
    ap.add_argument("--cdp-port", type=int, default=None)
    args = ap.parse_args()

    cfg = load_account(args.account)
    cdp_port = args.cdp_port or cfg.get("cdp_port") or (9222 if args.account == "account1" else 9223)
    cdp_url = "http://127.0.0.1:" + str(cdp_port)

    out_dir = Path(args.out_dir or (Path.home() / ".savia" / "captured-vtt" / args.account))
    out_dir.mkdir(parents=True, exist_ok=True)

    page = find_sp_page(cdp_url)
    if not page:
        sys.stderr.write("[sp-rec] no SP page in daemon for " + args.account + "\n"); sys.exit(3)
    sys.stderr.write("[sp-rec] using page: " + (page.get("url") or "")[:100] + "\n")

    ws = websocket.create_connection(page["webSocketDebuggerUrl"], timeout=30, suppress_origin=True)
    try:
        cdp_send(ws, 1, "Runtime.enable"); time.sleep(2)

        sys.stderr.write("[sp-rec] listing " + cfg["recordings_path"] + " ...\n")
        res = list_recordings(ws, cfg["personal_user"], cfg["drive_id"], cfg["recordings_path"])
        if not res or res.get("status") != 200:
            sys.stderr.write("[sp-rec] list FAIL: " + json.dumps(res or {})[:300] + "\n"); sys.exit(4)
        items = res.get("items", [])
        sys.stderr.write("[sp-rec] total in folder: " + str(len(items)) + "\n")

        cutoff = datetime.now(timezone.utc) - timedelta(days=args.since_days)
        fresh = []
        for it in items:
            mt = it.get("mtime") or ""
            try:
                m = datetime.fromisoformat(mt.replace("Z", "+00:00"))
            except Exception:
                continue
            if m >= cutoff:
                fresh.append(it)
        sys.stderr.write("[sp-rec] last " + str(args.since_days) + "d: " + str(len(fresh)) + "\n")

        listing_path = out_dir / ("listing-" + datetime.now().strftime("%Y%m%d-%H%M") + ".json")
        listing_path.write_text(json.dumps({
            "account": args.account,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "since_days": args.since_days,
            "items_count": len(fresh),
            "items": fresh,
        }, ensure_ascii=False, indent=2), encoding="utf-8")
        sys.stderr.write("[sp-rec] listing -> " + str(listing_path) + "\n")

        if args.action == "list":
            print(json.dumps({"account": args.account, "items": len(fresh), "listing": str(listing_path)}))
            return

        downloaded = 0; skipped = 0
        for it in fresh[: args.max]:
            base = it["name"].rsplit(".", 1)[0]
            target = out_dir / (base + ".vtt")
            if target.exists():
                skipped += 1; continue
            tr = fetch_transcript(ws, cfg["personal_user"], cfg["drive_id"], it["id"])
            if not tr or tr.get("status") != 200:
                sys.stderr.write("[sp-rec] no-vtt for " + base[:60] + ": " + json.dumps(tr or {})[:120] + "\n")
                continue
            target.write_text(tr.get("vtt") or "", encoding="utf-8")
            downloaded += 1
            sys.stderr.write("[sp-rec] saved: " + target.name + "\n")
        print(json.dumps({"account": args.account, "downloaded": downloaded, "skipped": skipped, "considered": len(fresh)}))
    finally:
        ws.close()


if __name__ == "__main__":
    main()
