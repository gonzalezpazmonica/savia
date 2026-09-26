#!/usr/bin/env python3
"""
savia-shield-daemon.py — Unified Savia Shield daemon
/scan /mask /unmask /health on localhost.
Fallback: if down, hooks exit 0. Claude Code always works.
"""
import http.server, json, os, re, sys, time, base64
from datetime import datetime, timezone
from pathlib import Path

PORT = int(os.environ.get("SAVIA_SHIELD_PORT", "8444"))
PROJ = os.environ.get("CLAUDE_PROJECT_DIR", str(Path(__file__).resolve().parent.parent))
CRED = [
    (r'AKIA[0-9A-Z]{16}', 'aws_key'),
    (r'ghp_[A-Za-z0-9]{36}', 'git'+'hub_pat'),
    (r'git'+'hub_pat_[A-Za-z0-9_]{82,}', 'git'+'hub_fine_pat'),
    (r'sk-(proj-)?[A-Za-z0-9]{32,}', 'openai_key'),
    (r'sv=20[0-9]{2}-', 'azure_sas'),
    (r'AIza[0-9A-Za-z_-]{35}', 'google_api_key'),
    (r'-----BEG'+'IN.*PRIV'+'ATE KEY-----', 'private_key'),
    (r'(jdbc:|mongodb\+srv://|Ser'+'ver=.*Pass'+'word=)', 'connection_string'),
    (r'(192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+)', 'internal_ip'),
]
ner = None; mmap = {}; rmap = {}

# NER false-positive mitigation (3 layers):
# 1. Allow-list loaded from shield-ner-allowlist.txt (editable without code changes)
# 2. Soft entity types (LOCATION/ORG) downgraded to WARN in docs/
# 3. Raised threshold (0.85 vs old 0.7) for BLOCK decisions
NER_SOFT_TYPES = {"LOCATION", "NRP", "ORGANIZATION"}
NER_BLOCK_THRESHOLD = 0.85

# Public provider domains — never block. Substring match (case-insensitive).
NER_PUBLIC_DOMAINS = (
    "microsoft.com", "microsoft365.com", "office.com", "office365.com",
    "sharepoint.com", "onedrive.live.com", "outlook.com",
    "outlook.office.com", "outlook.office365.com", "stream.office.com",
    "login.microsoftonline.com", "login.live.com",
    "graph.microsoft.com", "teams.microsoft.com",
    "google.com", "gmail.com", "googleapis.com", "drive.google.com",
    "github.com", "gitlab.com", "bitbucket.org", "dev.azure.com",
    "anthropic.com", "claude.com", "openai.com",
)

# File extensions — entity texts ending in these are paths, not PII
NER_PATH_EXTENSIONS = (
    ".py", ".js", ".ts", ".sh", ".md", ".json", ".yml", ".yaml",
    ".txt", ".html", ".css", ".vue", ".tsx", ".jsx", ".rs", ".go",
    ".java", ".rb", ".php", ".toml", ".ini", ".cfg", ".xml", ".log",
)

def _load_allowlist():
    """Load technical terms from shield-ner-allowlist.txt."""
    p = Path(__file__).parent / "shield-ner-allowlist.txt"
    terms = set()
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                terms.add(line)
    return terms, {t.lower() for t in terms}

NER_ALLOW_LIST, NER_ALLOW_LOWER = _load_allowlist()


def init():
    global ner, mmap, rmap
    t0 = time.time()
    for p in [f'{PROJ}/config.local/savia-shield/mask-map.json',
              f'{PROJ}/output/data-sovereignty-validation/mask-map.json']:
        if os.path.exists(p):
            with open(p,'r') as f: mmap=json.load(f); rmap={v:k for k,v in mmap.items()}
            print(f"  Mask: {len(mmap)} entities",file=sys.stderr); break
    try:
        from presidio_analyzer import AnalyzerEngine,PatternRecognizer
        from presidio_analyzer.nlp_engine import SpacyNlpEngine
        # Load both ES and EN models for better multilingual accuracy
        models = [{"lang_code":"es","model_name":"es_core_news_md"}]
        try:
            import spacy
            spacy.load("en_core_web_md")
            models.append({"lang_code":"en","model_name":"en_core_web_md"})
            print("  EN model: en_core_web_md loaded",file=sys.stderr)
        except Exception:
            print("  EN model: not available (install: python -m spacy download en_core_web_md)",file=sys.stderr)
        nlp=SpacyNlpEngine(models=models)
        ner_eng=AnalyzerEngine(nlp_engine=nlp,supported_languages=["es","en"])
        for g in Path(PROJ).glob("projects/*/GLOSSARY-MASK.md"):
            cat=None; ents={}
            with open(g,'r') as f:
                for ln in f:
                    ln=ln.strip()
                    if ln.startswith('## '): cat=ln[3:].strip().lower(); ents.setdefault(cat,[])
                    elif ln.startswith('- **') and cat:
                        t=ln.split('**')[1] if '**' in ln else ''
                        if t and len(t)>1: ents[cat].append(t)
            for c,terms in ents.items():
                if terms:
                    for la in ["es","en"]:
                        ner_eng.registry.add_recognizer(PatternRecognizer(
                            supported_entity=f"CUSTOM_{c.upper()}",deny_list=terms,supported_language=la))
            print(f"  Glossary: {sum(len(v) for v in ents.values())} terms",file=sys.stderr); break
        globals()['ner']=ner_eng
        print(f"  NER: {len(ner_eng.registry.recognizers)} recognizers",file=sys.stderr)
        print(f"  Allow-list: {len(NER_ALLOW_LIST)} technical terms",file=sys.stderr)
        print(f"  Block threshold: {NER_BLOCK_THRESHOLD}",file=sys.stderr)
    except Exception as e: print(f"  NER unavailable: {e}",file=sys.stderr)
    print(f"  Boot: {time.time()-t0:.1f}s",file=sys.stderr)

def scan(text, th=None, file_path=""):
    """Scan text for PII using regex (layer 1) + NER (layer 1.5).
    Three NER filters reduce false positives:
    1. Allow-list of technical terms (NER_ALLOW_LIST)
    2. Soft entity types (LOCATION/ORG) downgraded to WARN in docs
    3. Raised threshold (0.85) for BLOCK decisions
    """
    if th is None:
        th = NER_BLOCK_THRESHOLD
    t0 = time.time()
    hits = []
    # Layer 1: regex credentials (always block, score 1.0)
    for p, t2 in CRED:
        for m in re.finditer(p, text, re.I):
            hits.append({"type": t2, "text": m.group(),
                         "score": 1.0, "action": "BLOCK", "layer": 1})
    # Layer 1b: base64-encoded credentials
    for blob in re.findall(r'[A-Za-z0-9+/]{40,200}={0,2}', text)[:20]:
        try:
            dec = base64.b64decode(blob).decode('utf-8', errors='ignore')
        except (base64.binascii.Error, ValueError):
            continue
        for p, t2 in CRED:
            if re.search(p, dec, re.I):
                hits.append({"type": f"b64_{t2}", "text": blob[:30] + "...",
                             "score": 1.0, "action": "BLOCK", "layer": 1})
    # Layer 1.5: NER with 3 filters
    if ner and len(text) >= 10:
        fp_norm = file_path.replace("\\", "/")
        is_docs = "/docs/" in fp_norm or "/savia-models/" in fp_norm
        for la in ["es", "en"]:
            try:
                results = ner.analyze(text=text, language=la,
                                      score_threshold=0.4)
            except Exception as e:
                print(f"  NER {la} error: {e}", file=sys.stderr)
                continue
            for r in results:
                entity_text = text[r.start:r.end]
                # Filter -1: skip very short alphanumeric tokens (H19, S3, M1)
                if len(entity_text) <= 4 and re.match(r'^[A-Za-z0-9]+$', entity_text):
                    continue
                # Filter -0.5: skip ISO dates (2026-04-02), version strings (v4.1.1),
                # and Claude model IDs (claude-haiku-4-5-20251001, claude-sonnet-4-6, etc.)
                if re.match(r'^(20\d{2}-\d{2}-\d{2}|v?\d+\.\d+(\.\d+)?)$', entity_text):
                    continue
                if re.search(r'claude-(opus|sonnet|haiku)-[\d]', entity_text) or \
                   re.match(r'^\d+-\d+-\d{8,}$', entity_text):
                    continue
                # Filter -0.3: skip code-like patterns (function calls, variables, keywords)
                if re.search(r'[(\[{]|^\w+\.\w+$|^(print|def |class |import |self\.|ctx\.|page)', entity_text):
                    continue
                # Filter -0.2: skip common English phrases misclassified as ORG/PERSON
                if entity_text.lower() in ("too vague", "check", "respond", "pages", "ensure_ascii"):
                    continue
                # Filter 0: skip entities that ARE URLs or are inside URLs
                if entity_text.startswith(("http://", "https://")):
                    continue
                ctx_start = max(0, r.start - 50)
                context = text[ctx_start:r.end + 10]
                if re.search(r'https?://\S*' + re.escape(entity_text), context):
                    continue
                # Filter 0a: public provider domains (MS, Google, GitHub, etc.)
                etl = entity_text.lower()
                if any(d in etl for d in NER_PUBLIC_DOMAINS):
                    continue
                # Filter 0b: code-like identifiers (UPPER_SNAKE, lower_snake, dotted)
                if re.match(r'^[A-Z][A-Z0-9_]{2,}$', entity_text):
                    continue
                # snake_case identifiers (folder_path, mail_url, session_dir)
                if "_" in entity_text and re.match(r'^[A-Za-z_][A-Za-z0-9_]+$', entity_text):
                    continue
                if re.match(r'^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_.]*$', entity_text):
                    continue
                # Filter 0c: path fragments (contains / or known code extensions)
                if "/" in entity_text or "\\" in entity_text:
                    continue
                if etl.endswith(NER_PATH_EXTENSIONS):
                    continue
                # Filter 0d: workspace path markers (user's own path is not PII)
                if "onedrive - " in etl or "/documentos/" in etl or "/documents/" in etl:
                    continue
                # Filter 0e: keyword argument fragments (encoding="utf-8", name="foo")
                # Presidio sometimes marks the truncated left side as PERSON/ORG.
                if re.search(r'\w+\s*=\s*["\']', entity_text):
                    continue
                # Filter 0f: entity with unbalanced quotes = truncated literal, skip
                if entity_text.count('"') == 1 or entity_text.count("'") == 1:
                    continue
                # Filter 1: allow-list of technical terms
                # Check both exact match and all-words-in-allowlist
                # Markdown/punctuation (e.g. "## Qué", "**Sonnet**") is stripped per
                # word so mandated headings don't defeat the allow-list.
                et_lower = entity_text.lower()
                if et_lower in NER_ALLOW_LOWER:
                    continue
                words = [w.strip("#*`>_:-.,;!?¿¡()[]\"'") for w in et_lower.split()]
                words = [w for w in words if w]
                if words and all(w in NER_ALLOW_LOWER for w in words):
                    continue
                # Filter 2: soft types in docs — warn only
                if is_docs and r.entity_type in NER_SOFT_TYPES:
                    hits.append({"type": r.entity_type, "text": entity_text,
                                 "score": round(r.score, 2),
                                 "action": "WARN", "layer": 1.5})
                    continue
                # Filter 3: raised threshold for block
                action = "BLOCK" if r.score >= th else "WARN"
                hits.append({"type": r.entity_type, "text": entity_text,
                             "score": round(r.score, 2),
                             "action": action, "layer": 1.5})
    # Deduplicate
    seen = set()
    dd = []
    for h in hits:
        k = (h["text"], h["type"])
        if k not in seen:
            seen.add(k)
            dd.append(h)
    return {
        "verdict": "PII_DETECTED" if any(
            h["action"] == "BLOCK" for h in dd) else "CLEAN",
        "entities": dd,
        "latency_ms": int((time.time() - t0) * 1000)
    }

def mask(text):
    t0=time.time(); o=text
    for t in sorted(mmap.keys(),key=len,reverse=True): text=re.sub(re.escape(t),mmap[t],text,flags=re.I)
    for p,t2 in CRED: text=re.sub(p,f'[REDACTED_{t2.upper()}]',text,flags=re.I)
    return {"masked":text,"changed":text!=o,"latency_ms":int((time.time()-t0)*1000)}

def unmask(text):
    t0=time.time()
    for m in sorted(rmap.keys(),key=len,reverse=True): text=text.replace(m,rmap[m])
    return {"unmasked":text,"latency_ms":int((time.time()-t0)*1000)}

TOKEN = ""
def load_token():
    global TOKEN
    tp = os.path.expanduser("~/.savia/shield-token")
    if os.path.exists(tp):
        with open(tp) as f: TOKEN = f.read().strip()
        print(f"  Auth: token loaded", file=sys.stderr)
    else:
        TOKEN = ""
        print(f"  Auth: NO TOKEN (open access!)", file=sys.stderr)


def gate(hook_input):
    """Unified gate: parse hook JSON, classify destination, scan regex+NER."""
    t0 = time.time()
    ti = hook_input.get("tool_input", {})
    fp = ti.get("file_path", ti.get("path", ""))
    content = ti.get("content", ti.get("new_string", ""))[:20000]

    if not fp:
        return {"verdict": "ALLOW", "reason": "no_file_path", "latency_ms": 0}

    # Normalize path separators (Windows uses \, patterns use /)
    fp_norm = fp.replace("\\", "/")

    # Destination classification — private paths skip scanning
    private_patterns = ["/projects/", "projects/", ".local.", "/output/", "private-agent-memory",
                        "config.local", "/.savia/", "/.claude/sessions/", "settings.local.json"]
    for pat in private_patterns:
        if pat in fp_norm:
            return {"verdict": "ALLOW", "reason": "private_destination", "latency_ms": 0}

    # Whitelist for shield's own files — require specific directory prefixes
    shield_patterns = [
        "scripts/data-sovereignty", "scripts/ollama-classify", "scripts/shield-ner",
        "scripts/savia-shield", "scripts/pre-commit-sovereignty",
        "scripts/sovereignty-classify", "scripts/sovereignty-decide",
        "hooks/data-sovereignty", "hooks/ollama-classify", "hooks/shield-ner",
        "tests/test-data-sovereignty", "tests/test-savia-shield", "tests/test-shield-daemon",
        "tests/test-sovereignty", "tests/test-prompt-injection-guard",
        "docs/propuestas/SE-314", "config/telemetry-schema", "config/telemetry-policies",
        "config/sovereignty-thresholds", "config/classifier",
    ]
    for pat in shield_patterns:
        if pat in fp_norm:
            return {"verdict": "ALLOW", "reason": "shield_file", "latency_ms": 0}

    if not content or len(content) < 10:
        return {"verdict": "ALLOW", "reason": "trivial_content", "latency_ms": 0}

    # NFKC normalize
    import unicodedata
    content = unicodedata.normalize("NFKC", content)

    # Cross-write detection: if file exists, combine existing + new content
    crosswrite_pat = re.compile(r'Server=.*[Pp]assword=|[Pp]assword=.*Server=', re.I)
    # Resolve Git Bash paths on Windows (/tmp/... -> C:\Users\...\Temp\...)
    fp_disk = fp
    if not os.path.isfile(fp_disk) and sys.platform == 'win32' and fp.startswith('/'):
        import subprocess as _sp
        try:
            _r = _sp.run(['cygpath', '-w', fp], capture_output=True, text=True, timeout=2)
            if _r.returncode == 0 and _r.stdout.strip():
                fp_disk = _r.stdout.strip()
        except Exception:
            pass
    if os.path.isfile(fp_disk):
        try:
            with open(fp_disk, 'r', encoding='utf-8', errors='ignore') as f:
                existing = f.read(10000)
            combined = existing + " " + content
            if crosswrite_pat.search(combined):
                return {"verdict": "BLOCK",
                        "entities": [{"type": "split_write", "text": "credential split across writes",
                                      "score": 1.0, "action": "BLOCK", "layer": 1}],
                        "file": fp_norm, "latency_ms": int((time.time() - t0) * 1000)}
        except Exception:
            pass

    # Scan (regex + NER combined) — pass file_path for context-aware filtering
    result = scan(content, file_path=fp_norm)

    latency = int((time.time() - t0) * 1000)
    verdict = "BLOCK" if result["verdict"] == "PII_DETECTED" else "ALLOW"
    return {"verdict": verdict, "entities": result.get("entities", []),
            "file": fp, "latency_ms": latency}

def _ollama_model_loaded():
    """Probe Ollama for classification model presence. Returns bool. Never raises."""
    try:
        import urllib.request
        model = os.environ.get("OLLAMA_CLASSIFY_MODEL", "qwen2.5:7b")
        url = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434") + "/api/tags"
        with urllib.request.urlopen(url, timeout=2) as r:
            tags = json.loads(r.read().decode())
            return any(m.get("name", "").startswith(model) for m in tags.get("models", []))
    except Exception:
        return False


class H(http.server.BaseHTTPRequestHandler):
    def _check_auth(self):

        if not TOKEN: return True
        auth = self.headers.get('X-Shield-Token', '')
        if auth != TOKEN:
            return False
        return True
    def _j(self):
        n=int(self.headers.get('Content-Length',0))
        if n > 1048576: raise ValueError('Request too large (max 1MB)')
        return json.loads(self.rfile.read(n)) if n else {}
    def _r(self,d,s=200):
        b=json.dumps(d,ensure_ascii=False).encode(); self.send_response(s)
        self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        if not self._check_auth():
            self._r({"error":"unauthorized"},403); return
        try:
            d=self._j(); t=d.get("text","")
            if self.path=="/scan": self._r(scan(t,d.get("threshold",0.7)))
            elif self.path=="/mask": self._r(mask(t))
            elif self.path=="/unmask": self._r(unmask(t))
            elif self.path=="/gate": self._r(gate(d))
            else: self._r({"error":"not found"},404)
        except Exception as e: self._r({"error":str(e)},500)
    def do_GET(self):
        if self.path=="/health":
            self._r({"status":"ok","ner":ner is not None,"version":"2.0",
                     "ollama_model_loaded": _ollama_model_loaded(),
                     "ollama_model": os.environ.get("OLLAMA_CLASSIFY_MODEL","qwen2.5:7b")})
        else: self._r({"error":"not found"},404)
    def log_message(self,*a): pass

if __name__=='__main__':
    import argparse; p=argparse.ArgumentParser(); p.add_argument('--port',type=int,default=PORT)
    a=p.parse_args(); print(f"Savia Shield Daemon :{a.port}",file=sys.stderr); init(); load_token()
    s=http.server.HTTPServer(('127.0.0.1',a.port),H); print(f"  Ready",file=sys.stderr)
    try: s.serve_forever()
    except KeyboardInterrupt: print("\nStopped.",file=sys.stderr)
