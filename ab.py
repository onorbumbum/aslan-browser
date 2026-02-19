#!/usr/bin/env python3
"""Quick CLI helper for interactive aslan-browser control."""
import sys, json, time
from aslan_browser import AslanBrowser

b = AslanBrowser()
cmd = sys.argv[1] if len(sys.argv) > 1 else "tree"

try:
    if cmd == "nav":
        url = sys.argv[2]
        wait = sys.argv[3] if len(sys.argv) > 3 else "load"
        r = b.navigate(url, wait_until=wait)
        print(json.dumps(r, indent=2))

    elif cmd == "tree":
        tree = b.get_accessibility_tree()
        for n in tree:
            ref = n.get("ref","?")
            role = n.get("role","?")
            name = n.get("name","")[:70]
            val = n.get("value","")
            extra = f'  value="{val}"' if val else ""
            print(f"{ref:8s} {role:14s} \"{name}\"{extra}")
        print(f"\n({len(tree)} total nodes)")

    elif cmd == "click":
        target = sys.argv[2]
        b.click(target)
        print(f"Clicked {target}")

    elif cmd == "fill":
        target = sys.argv[2]
        value = sys.argv[3]
        b.fill(target, value)
        print(f"Filled {target} with '{value}'")

    elif cmd == "type":
        # fill + small delay, for search boxes etc
        target = sys.argv[2]
        value = sys.argv[3]
        b.click(target)
        time.sleep(0.2)
        b.fill(target, value)
        print(f"Typed '{value}' into {target}")

    elif cmd == "key":
        key = sys.argv[2]
        b.keypress(key)
        print(f"Pressed {key}")

    elif cmd == "shot":
        path = sys.argv[2] if len(sys.argv) > 2 else "/tmp/aslan-live.jpg"
        quality = int(sys.argv[3]) if len(sys.argv) > 3 else 70
        size = b.save_screenshot(path, quality=quality)
        print(f"Screenshot saved: {path} ({size:,} bytes)")

    elif cmd == "url":
        print(b.get_url())

    elif cmd == "title":
        print(b.get_title())

    elif cmd == "eval":
        script = sys.argv[2]
        r = b.evaluate(script)
        print(r)

    elif cmd == "scroll":
        x = float(sys.argv[2]) if len(sys.argv) > 2 else 0
        y = float(sys.argv[3]) if len(sys.argv) > 3 else 500
        b.scroll(x, y)
        print(f"Scrolled to ({x}, {y})")

    elif cmd == "back":
        r = b.go_back()
        print(json.dumps(r, indent=2))

    elif cmd == "wait":
        secs = float(sys.argv[2]) if len(sys.argv) > 2 else 1
        time.sleep(secs)
        print(f"Waited {secs}s")

    else:
        print(f"Unknown command: {cmd}")
        print("Commands: nav, tree, click, fill, type, key, shot, url, title, eval, scroll, back, wait")

finally:
    b.close()
