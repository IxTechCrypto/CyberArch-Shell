#!/usr/bin/env bash
# cache-news.sh — fetches BBC + Google News RSS, writes headlines to /tmp/cyberpunk-news-cache.json
# run via cron: */10 * * * * ~/.config/hypr/themes/cyberpunk/components/login/sddm-theme/cache-news.sh
#
# feed text is untrusted: it only ever reaches python as file contents, never as shell or code

CACHE="/tmp/cyberpunk-news-cache.json"
CITY_FILE="$HOME/.config/cyberarch/city.json"
[ -r "$CITY_FILE" ] || CITY_FILE="$HOME/.config/hypr/themes/cyberpunk/config/city.json"

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

city="$(python3 - "$CITY_FILE" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get("full") or d.get("name") or "US")
except Exception:
    print("US")
PY
)"
[ -n "$city" ] || city="US"

global_url="https://feeds.bbci.co.uk/news/world/rss.xml"
local_url="https://news.google.com/rss/search?q=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1] + " news when:2d"))' "$city")&hl=en-US&gl=US&ceid=US:en"

curl -sfL --max-time 8 -H "User-Agent: Mozilla/5.0" -o "$WORK/global.xml" "$global_url"
curl -sfL --max-time 8 -H "User-Agent: Mozilla/5.0" -o "$WORK/local.xml" "$local_url"

python3 - "$WORK/global.xml" "$WORK/local.xml" "$WORK/out.json" <<'PY' 2>/dev/null
import html, json, re, sys

def titles(path):
    try:
        raw = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return []
    out = []
    for block in re.finditer(r"<(item|entry)\b.*?</\1>", raw, re.S):
        m = re.search(r"<title[^>]*>(.*?)</title>", block.group(0), re.S)
        if not m:
            continue
        t = re.sub(r"<!\[CDATA\[(.*?)\]\]>", r"\1", m.group(1), flags=re.S)
        t = re.sub(r"<[^>]*>", "", t)
        t = " ".join(html.unescape(t).split())
        if t:
            out.append(t)
        if len(out) == 7:
            break
    return out

g, l = titles(sys.argv[1]), titles(sys.argv[2])
mixed = []
for i in range(max(len(g), len(l))):
    if i < len(g): mixed.append(g[i])
    if i < len(l): mixed.append(l[i])
with open(sys.argv[3], "w", encoding="utf-8") as f:
    json.dump(mixed[:14], f, ensure_ascii=False)
PY

[ -s "$WORK/out.json" ] || echo "[]" > "$WORK/out.json"
cp -f "$WORK/out.json" "$CACHE"
