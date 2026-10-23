"""CodeQL #50/#51 (py/incomplete-url-substring-sanitization).

sp-recordings.py and teams_attachments.py chose the CDP tab whose URL merely
contained "sharepoint.com" / "teams.". JavaScript then ran inside that tab and
sp-recordings sent user and drive ids to its window.location.origin, so a tab
like https://evil.example/?u=sharepoint.com received them. Selection now
checks the parsed hostname.
"""
import importlib.util
import json
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def _load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    # websocket-client is only needed at runtime against a live daemon.
    with patch.dict(sys.modules, {"websocket": types.ModuleType("websocket")}):
        spec.loader.exec_module(module)
    return module


sp = _load("sp_recordings_under_test", "sp-recordings.py")
teams = _load("teams_attachments_under_test", "teams_attachments.py")

EVIL = [
    "https://evil.example/?next=sharepoint.com",
    "https://sharepoint.com.evil.example/",
    "https://evilsharepoint.com/",
    "https://evil.example/teams.microsoft.com",
    "http://contoso.sharepoint.com/",
    "javascript:alert('sharepoint.com')",
    "",
]


def _page(url):
    return {"type": "page", "url": url, "webSocketDebuggerUrl": "ws://x/" + url}


class _Resp:
    def __init__(self, targets):
        self._body = json.dumps(targets).encode()

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class SharePointSelectionTests(unittest.TestCase):
    def test_lookalike_tabs_are_never_selected(self):
        for url in EVIL:
            self.assertFalse(sp.is_sharepoint_url(url), url)

    def test_real_tenant_tab_is_selected_even_after_lookalikes(self):
        real = "https://contoso-my.sharepoint.com/personal/x/_layouts/15/onedrive.aspx"
        targets = [_page(u) for u in EVIL] + [_page(real)]
        with patch.object(sp.urllib.request, "urlopen", return_value=_Resp(targets)):
            page = sp.find_sp_page("http://127.0.0.1:9222")
        self.assertEqual(page["url"], real)

    def test_no_tab_when_only_lookalikes(self):
        targets = [_page(u) for u in EVIL]
        with patch.object(sp.urllib.request, "urlopen", return_value=_Resp(targets)):
            self.assertIsNone(sp.find_sp_page("http://127.0.0.1:9222"))


class TeamsSelectionTests(unittest.TestCase):
    def test_lookalike_tabs_are_never_selected(self):
        self.assertIsNone(teams.pick_authenticated_page([_page(u) for u in EVIL]))

    def test_teams_and_sharepoint_hosts_are_accepted(self):
        for url in ("https://teams.microsoft.com/v2/", "https://teams.cloud.microsoft/",
                    "https://contoso.sharepoint.com/sites/x"):
            page = teams.pick_authenticated_page([_page(EVIL[0]), _page(url)])
            self.assertEqual(page["url"], url)


if __name__ == "__main__":
    unittest.main()
