#!/usr/bin/env python3
"""封版并安装「雾青」主题包：
   评审稿 → plugins-market/theme-misty-teal（reviewed: true + reviewedHash）
          → ~/Library/Application Support/MarkNote/plugins/theme-misty-teal

用法: python3 scripts/publish-misty-teal.py [--dry-run]
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REVIEW = ROOT / "plugins-market/_review/theme-misty-teal-v1"
MARKET = ROOT / "plugins-market/theme-misty-teal"
INSTALL = (Path.home() / "Library/Application Support/MarkNote/plugins/theme-misty-teal")
HASHER = ROOT / "scripts/theme-hash.swift"


def stage(src, dst, reviewed):
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    theme = dst / "theme.json"
    entries = json.loads(theme.read_text(encoding="utf-8"))
    for e in entries:
        e.pop("reviewedHash", None)
        e["reviewed"] = reviewed
    theme.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return entries


def main():
    dry = "--dry-run" in sys.argv
    # 1. 市场目录（reviewed=true，先不写 hash）
    entries = stage(REVIEW, MARKET, True)
    # 2. 用与 App 相同的算法算哈希
    out = subprocess.run(["swift", str(HASHER), str(MARKET)], capture_output=True, text=True)
    if out.returncode != 0:
        print(out.stdout, out.stderr, file=sys.stderr)
        raise SystemExit("计算 reviewedHash 失败")
    digest = out.stdout.strip()
    print(f"reviewedHash = {digest}")
    if dry:
        return
    # 3. 写回 theme.json（hash 不参与自身计算）
    theme = MARKET / "theme.json"
    entries = json.loads(theme.read_text(encoding="utf-8"))
    for e in entries:
        e["reviewedHash"] = digest
    theme.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    # 4. 安装到应用插件目录
    INSTALL.parent.mkdir(parents=True, exist_ok=True)
    if INSTALL.exists():
        shutil.rmtree(INSTALL)
    shutil.copytree(MARKET, INSTALL)
    print(f"市场目录: {MARKET}")
    print(f"已安装:   {INSTALL}")


if __name__ == "__main__":
    main()
