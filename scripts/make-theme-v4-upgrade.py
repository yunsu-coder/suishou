#!/usr/bin/env python3
"""把已上线的老主题升到 auditVersion 4：
    复制到 plugins-market/_review/<id>-v4/ → 只改不达标的提示色 / 高亮色 → 标 auditVersion 4
（不封 reviewedHash：按规矩等你人工审核通过后再封版安装。）

用法: python3 scripts/make-theme-v4-upgrade.py
"""

import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MARKET = ROOT / "plugins-market"

# 只动这些不达标的色值：同色相加深，直到通过「提示色 ≥4.0 / 高亮 ≥3.0」
FIXES = {
    "theme-bubble-pop": {
        "bubble-pop-light.css": {
            "--note": "#6A38F0",
            "--tip": "#257E53",
            "--warn": "#8A6208",
            "--danger": "#B93558",
            "--info": "#2566AE",
            "--hl-comment": "#7A6E86",
        },
    },
    "theme-sumi-paper": {
        "sumi-day.css": {
            "--warn": "#8A6216",
        },
    },
}


def hex_to_rgb(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lum(rgb):
    f = lambda c: (c / 255) / 12.92 if c / 255 <= 0.03928 else (((c / 255) + 0.055) / 1.055) ** 2.4
    r, g, b = (f(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def value_of(css, key):
    m = re.search(rf"{re.escape(key)}\s*:\s*([^;]+);", css)
    return m.group(1).strip() if m else None


def rgba_of(value):
    m = re.fullmatch(r"rgba?\(([^)]*)\)", value.strip())
    if not m:
        c = hex_to_rgb(value)
        return c, 1.0
    parts = [p.strip() for p in m.group(1).split(",")]
    return tuple(int(float(p)) for p in parts[:3]), (float(parts[3]) if len(parts) > 3 else 1.0)


def over(fg, alpha, bg):
    return tuple(round(fg[i] * alpha + bg[i] * (1 - alpha)) for i in range(3))


def main():
    for pkg_id, files in FIXES.items():
        src = MARKET / pkg_id
        dst = MARKET / "_review" / f"{pkg_id}-v4"
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
        # theme.json：升版本、去掉封存
        theme = dst / "theme.json"
        entries = json.loads(theme.read_text(encoding="utf-8"))
        for e in entries:
            e["auditVersion"] = 4
            e["reviewed"] = False
            e.pop("reviewedHash", None)
        theme.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

        print(f"== {pkg_id} → _review/{pkg_id}-v4")
        for css_name, changes in files.items():
            path = dst / css_name
            css = path.read_text(encoding="utf-8")
            bg = hex_to_rgb(value_of(css, "--bg"))
            code_bg = hex_to_rgb(value_of(css, "--code-bg"))
            for key, new_value in changes.items():
                old_value = value_of(css, key)
                css = re.sub(rf"({re.escape(key)}\s*:\s*)([^;]+)(;)", rf"\g<1>{new_value}\g<3>", css, count=1)
                if key.startswith("--hl-"):
                    old_r = contrast(hex_to_rgb(old_value), code_bg)
                    new_r = contrast(hex_to_rgb(new_value), code_bg)
                    base = "代码底"
                else:
                    old_rgb, old_a = rgba_of(value_of(css, key + "-bg"))
                    old_r = contrast(hex_to_rgb(old_value), over(old_rgb, old_a, bg))
                    new_rgb, new_a = rgba_of(value_of(css, key + "-bg"))
                    new_r = contrast(hex_to_rgb(new_value), over(new_rgb, new_a, bg))
                    base = "自身提示底"
                print(f"   {key:<14} {old_value:<9} → {new_value:<9} （{base}对比 {old_r:.2f} → {new_r:.2f}）")
            path.write_text(css, encoding="utf-8")
    print("\n完成：候选稿在 plugins-market/_review/<id>-v4/，等你审核通过后再封 reviewedHash 并安装。")


if __name__ == "__main__":
    main()
