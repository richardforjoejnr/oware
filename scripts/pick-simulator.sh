#!/usr/bin/env bash
# Prints the name of the newest available iPhone simulator (e.g. "iPhone 17 Pro").
set -euo pipefail
xcrun simctl list devices available -j \
  | python3 -c 'import json,sys,re
d=json.load(sys.stdin)["devices"]
names=[dev["name"] for rt,devs in d.items() if "iOS" in rt for dev in devs if dev["name"].startswith("iPhone") and dev["isAvailable"]]
def key(n):
    m=re.search(r"(\d+)",n); return (int(m.group(1)) if m else 0, "Pro" in n, len(n))
print(sorted(names,key=key)[-1] if names else "iPhone 16")'
