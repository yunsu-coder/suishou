#!/usr/bin/env bash
# 重新抓取 Resources/vendor/ 的全部前端依赖（离线可用，无需网络即可运行 app）
# 来源可完全复现：
#   npm:      markdown-it@14 dist/markdown-it.min.js        (UMD)
#             markdown-it-emoji dist/markdown-it-emoji.min.js
#             markdown-it-footnote dist/markdown-it-footnote.min.js
#             katex dist/katex.min.js + katex.min.css + fonts/
#             mermaid dist/mermaid.min.js
#   GitHub:   highlightjs/cdn-release@10.7.3 build/highlight.min.js (common, 41 语言)
set -e
V="$(cd "$(dirname "$0")/.." && pwd)/Resources/vendor"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
npm init -y >/dev/null
npm install --silent markdown-it@14 markdown-it-emoji markdown-it-footnote katex mermaid \
             markdown-it-sub markdown-it-sup markdown-it-mark markdown-it-ins markdown-it-task-lists
cp node_modules/markdown-it/dist/markdown-it.min.js "$V/"
cp node_modules/markdown-it-emoji/dist/markdown-it-emoji.min.js "$V/"
cp node_modules/markdown-it-footnote/dist/markdown-it-footnote.min.js "$V/"
cp node_modules/katex/dist/katex.min.js node_modules/katex/dist/katex.min.css "$V/"
cp -R node_modules/katex/dist/fonts "$V/"
cp node_modules/mermaid/dist/mermaid.min.js "$V/"
cp node_modules/markdown-it-sub/dist/markdown-it-sub.min.js "$V/"
cp node_modules/markdown-it-sup/dist/markdown-it-sup.min.js "$V/"
cp node_modules/markdown-it-mark/dist/markdown-it-mark.min.js "$V/"
cp node_modules/markdown-it-ins/dist/markdown-it-ins.min.js "$V/"
cp node_modules/markdown-it-task-lists/dist/markdown-it-task-lists.min.js "$V/"
curl -sL -o "$V/highlight.min.js" "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@10.7.3/build/highlight.min.js"
echo "vendor 已更新 ($(du -sh "$V" | cut -f1))"
