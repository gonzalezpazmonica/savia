#!/usr/bin/env python3
"""
kg-extract.py — Sovereign Knowledge Graph extraction from text.

Zero external dependencies beyond Python stdlib.
Three extraction modes:
  1. deterministic — regex patterns, fast, exact, confidence=1.0
  2. llm — via ProviderRouter (SE-294), contextual
  3. hybrid — regex first, LLM for uncovered sections

Usage:
  python3 kg-extract.py --mode deterministic --input doc.txt
  python3 kg-extract.py --mode hybrid --input doc.txt --source doc.pdf
   python3 kg-extract.py --mode ece --vault example-context
"""
import sys, json, re, hashlib, os, argparse
from collections import defaultdict

# ── Deterministic patterns ──────────────────────────────────────────────
PATTERNS = {
    "date": {
        "regex": re.compile(
            r"\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}/\d{1,2}/\d{4}\b"
        ),
        "entity_type": "event",
        "label_template": "Date: {value}",
    },
    "email": {
        "regex": re.compile(r"\b[\w.+-]+@[\w-]+\.[\w.-]+\b"),
        "entity_type": "person",
        "label_template": "Email: {value}",
    },
    "url": {
        "regex": re.compile(r"https?://[^\s<>\"\']+"),
        "entity_type": "document",
        "label_template": "URL: {value}",
    },
    "spec_id": {
        "regex": re.compile(r"\bSE-\d{2,4}\b"),
        "entity_type": "document",
        "label_template": "Spec: {value}",
    },
    "pr_ref": {
        "regex": re.compile(r"\bPR\s*#?\d{2,5}\b|(?<!\w)#\d{3,5}\b"),
        "entity_type": "event",
        "label_template": "PR: {value}",
    },
    "version": {
        "regex": re.compile(r"\bv?\d+\.\d+(?:\.\d+)?(?:-[a-zA-Z]+\d*)?\b"),
        "entity_type": "system",
        "label_template": "Version: {value}",
    },
    "file_path": {
        "regex": re.compile(r"\b[\w.-]+(?:/[\w.-]+)+\.\w{2,5}\b"),
        "entity_type": "document",
        "label_template": "File: {value}",
    },
    "person_name": {
        "regex": re.compile(
            r"\b[A-ZÁÉÍÓÚÑ][a-záéíóúñ]+(?:\s+[A-ZÁÉÍÓÚÑ][a-záéíóúñ]+){1,3}\b"
        ),
        "entity_type": "person",
        "label_template": "Person: {value}",
    },
    "percentage": {
        "regex": re.compile(r"\b\d{1,3}(?:\.\d+)?\s*%"),
        "entity_type": "event",
        "label_template": "Metric: {value}",
    },
    "money": {
        "regex": re.compile(
            r"\b[\$\€\£]?\s*\d{1,3}(?:,\d{3})*(?:\.\d{2})?\s*(?:EUR|USD|\€|\$|£)?\b"
        ),
        "entity_type": "event",
        "label_template": "Amount: {value}",
    },
    "commit_hash": {
        "regex": re.compile(r"\b[0-9a-f]{7,40}\b"),
        "entity_type": "event",
        "label_template": "Commit: {value}",
    },
    "agent_name": {
        "regex": re.compile(
            r"\b(?:architect|code-reviewer|business-analyst|"
            r"dotnet-developer|typescript-developer|frontend-developer|"
            r"python-developer|security-guardian|drift-auditor|"
            r"test-engineer|commit-guardian|configurator|"
            r"court-orchestrator|sdd-spec-writer|truth-tribunal|"
            r"dev-orchestrator|infrastructure-agent|diagram-architect|"
            r"pdf-digest|word-digest|excel-digest|meeting-digest|"
            r"tabular-analyst|tabular-intelligence|"
            r"reflection-validator|tech-writer|test-runner)\b"
        ),
        "entity_type": "system",
        "label_template": "Agent: {value}",
    },
}

# Patterns to skip (too generic, would produce noise)
SKIP_PATTERNS = {"commit_hash", "version"}


def content_hash(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()[:16]


class DeterministicExtractor:
    """Regex-based entity extraction. Zero deps, fast, exact."""

    def extract(self, text: str, source: str = "") -> dict:
        entities = []
        seen_spans = set()

        for pattern_name, pattern_def in PATTERNS.items():
            if pattern_name in SKIP_PATTERNS:
                continue
            for match in pattern_def["regex"].finditer(text):
                value = match.group().strip()
                span = (match.start(), match.end())
                span_key = f"{span[0]}-{span[1]}"

                if span_key in seen_spans:
                    continue
                seen_spans.add(span_key)

                context_start = max(0, span[0] - 60)
                context_end = min(len(text), span[1] + 60)
                evidence = text[context_start:context_end].strip()

                entity = {
                    "name": pattern_def["label_template"].format(value=value),
                    "type": pattern_def["entity_type"],
                    "value": value,
                    "confidence": 1.0,
                    "extraction_method": "regex",
                    "pattern": pattern_name,
                    "source_document": source,
                    "source_hash": content_hash(text),
                    "evidence_span": {
                        "start": span[0],
                        "end": span[1],
                        "text": evidence,
                    },
                    "verified_in_source": True,
                }
                entities.append(entity)

        # Deduplicate by name + type
        seen = {}
        unique = []
        for e in entities:
            key = f"{e['name']}|{e['type']}"
            if key not in seen:
                seen[key] = True
                unique.append(e)

        coverage = len(unique) / max(len(text.split()), 1)

        return {
            "source": source,
            "method": "deterministic",
            "entities": unique,
            "entity_count": len(unique),
            "coverage_pct": round(coverage * 100, 1),
            "needs_llm": coverage < 0.01,
        }


class LLMEnhancedExtractor:
    """Uses Savia's ProviderRouter for contextual entity extraction."""

    PROMPT_TEMPLATE = """Extract named entities and their relationships from the text below.
Return ONLY a JSON object with this structure:
{
  "entities": [
    {
      "name": "Entity Name",
      "type": "person|organization|system|document|event|project",
      "value": "exact text match from source",
      "evidence_span": "the exact sentence where this entity appears"
    }
  ],
  "relations": [
    {
      "source": "Entity A name",
      "target": "Entity B name",
      "relation": "MENTIONS|DEPENDS_ON|HAS_PART|RELATED_TO|CREATED_BY",
      "evidence": "the sentence that shows this relationship"
    }
  ]
}
Rules:
- Only extract entities VERBATIM from the text. Do not invent.
- Each entity MUST appear literally in the source.
- Max 15 entities. Quality over quantity.
- If unsure, omit.

Text:
{text}"""

    def __init__(self, router=None):
        self.router = router

    async def extract(self, text: str, source: str = "") -> dict:
        if self.router is None:
            return {
                "source": source,
                "method": "llm",
                "error": "ProviderRouter not available",
                "entities": [],
                "relations": [],
            }

        prompt = self.PROMPT_TEMPLATE.replace("{text}", text[:4000])

        try:
            response = await self.router.complete({
                "tier": "mid",
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.1,
                "max_tokens": 500,
            })

            content = response.content
            json_start = content.find("{")
            json_end = content.rfind("}") + 1
            if json_start >= 0 and json_end > json_start:
                data = json.loads(content[json_start:json_end])
            else:
                data = {"entities": [], "relations": []}

        except Exception:
            data = {"entities": [], "relations": []}

        # Enrich with metadata
        text_lower = text.lower()
        for e in data.get("entities", []):
            e["type"] = e.get("type", "document")
            e["confidence"] = 0.7
            e["extraction_method"] = "llm"
            e["source_document"] = source
            e["source_hash"] = content_hash(text)
            verified = e.get("value", "").lower() in text_lower
            e["verified_in_source"] = verified
            if e.get("evidence_span") and isinstance(e["evidence_span"], str):
                e["evidence_span"] = {"text": e["evidence_span"]}

        for r in data.get("relations", []):
            r["confidence"] = 0.6
            r["extraction_method"] = "llm"

        return {
            "source": source,
            "method": "llm",
            "entities": data.get("entities", []),
            "relations": data.get("relations", []),
            "entity_count": len(data.get("entities", [])),
        }


class HybridPipeline:
    """Regex first, LLM enhancement for uncovered sections."""

    def __init__(self, router=None):
        self.deterministic = DeterministicExtractor()
        self.llm = LLMEnhancedExtractor(router)
        self.llm_threshold = 0.5

    def extract_sync(self, text: str, source: str = "") -> dict:
        result = self.deterministic.extract(text, source)
        return result

    def quality_gate(self, entities: list[dict]) -> list[dict]:
        """Filter entities: reject hallucinated, tier by confidence."""
        filtered = []
        for e in entities:
            if not e.get("verified_in_source", False):
                e["status"] = "rejected"
                e["rejection_reason"] = "not found in source text"
                continue

            conf = e.get("confidence", 0)
            if conf < 0.5:
                e["status"] = "rejected"
                e["rejection_reason"] = "low confidence"
            elif conf < 0.7:
                e["status"] = "proposed"
            else:
                e["status"] = "active"

            filtered.append(e)
        return filtered


# ── CLI ─────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Sovereign KG extraction")
    parser.add_argument("--mode", default="deterministic",
                        choices=["deterministic", "llm", "hybrid", "ece"])
    parser.add_argument("--input", "-i", default="-",
                        help="Input file or - for stdin")
    parser.add_argument("--source", default="",
                        help="Source document identifier")
    parser.add_argument("--output", "-o", default="-",
                        help="Output file or - for stdout")
    parser.add_argument("--quality-gate", action="store_true",
                        help="Apply quality gate filtering")
    args = parser.parse_args()

    if args.input == "-":
        text = sys.stdin.read()
    else:
        with open(args.input) as f:
            text = f.read()

    source = args.source or args.input

    if args.mode == "deterministic":
        extractor = DeterministicExtractor()
        result = extractor.extract(text, source)
    elif args.mode == "hybrid":
        pipeline = HybridPipeline()
        result = pipeline.extract_sync(text, source)
    else:
        result = {"error": f"Mode '{args.mode}' requires ProviderRouter"}

    if args.quality_gate and "entities" in result:
        pipeline = HybridPipeline()
        result["entities"] = pipeline.quality_gate(result["entities"])
        result["entity_count"] = len(result["entities"])

    output = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output == "-":
        print(output)
    else:
        with open(args.output, "w") as f:
            f.write(output)

    return 0


if __name__ == "__main__":
    sys.exit(main())
