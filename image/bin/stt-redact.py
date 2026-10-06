#!/usr/bin/env python3
"""Replace secrets in every file under a directory. Used before the doctor zip."""
import os
import re
import sys
from pathlib import Path

KEY_RE = re.compile(r"TOKEN|KEY|SECRET|PASSWORD|PASS|AUTH|COOKIE", re.I)
HF_RE = re.compile(r"hf_[A-Za-z0-9]{20,}")


def secrets_from_env() -> list[str]:
    found = []
    for key, value in os.environ.items():
        if not value or len(value) < 6:
            continue
        if KEY_RE.search(key):
            found.append(value)
    found.sort(key=len, reverse=True)
    return found


def redact_text(text: str, secrets: list[str]) -> str:
    for secret in secrets:
        text = text.replace(secret, f"***redacted(len={len(secret)})***")
    text = HF_RE.sub(lambda m: f"***redacted(len={len(m.group(0))})***", text)
    return text


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: stt-redact.py DIRECTORY", file=sys.stderr)
        return 2
    root = Path(sys.argv[1])
    secrets = secrets_from_env()
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        data = path.read_bytes()
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            text = data.decode("utf-8", errors="replace")
        path.write_text(redact_text(text, secrets), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
