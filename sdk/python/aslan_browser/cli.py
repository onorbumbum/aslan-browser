"""Aslan Browser CLI — drive the browser from the command line."""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any, Optional

from aslan_browser import __version__
from aslan_browser.client import AslanBrowser, AslanBrowserError

_STATE_FILE = "/tmp/aslan-cli.json"


# ── State management ──────────────────────────────────────────────

def _load_state() -> dict:
    """Load CLI state from disk. Creates default if missing."""
    if os.path.exists(_STATE_FILE):
        try:
            with open(_STATE_FILE) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {"tab": "tab0"}


def _save_state(state: dict) -> None:
    """Write CLI state to disk."""
    with open(_STATE_FILE, "w") as f:
        json.dump(state, f)


def _current_tab(args: argparse.Namespace) -> str:
    """Resolve the target tab: explicit --tab flag, or current from state."""
    if hasattr(args, "tab") and args.tab:
        return args.tab
    return _load_state().get("tab", "tab0")


def _set_current_tab(tab_id: str) -> None:
    """Update the current tab in the state file."""
    state = _load_state()
    state["tab"] = tab_id
    _save_state(state)


# ── Connection helper ─────────────────────────────────────────────

def _connect() -> AslanBrowser:
    """Connect to Aslan Browser. auto_session=False — CLI is stateless per call."""
    return AslanBrowser(auto_session=False)


# ── Output formatting ─────────────────────────────────────────────

def _print_json(data: Any) -> None:
    """Print data as formatted JSON."""
    print(json.dumps(data, indent=2, ensure_ascii=False))


def _format_tree_node(node: dict) -> str:
    """Format one accessibility tree node as a compact line."""
    ref = node.get("ref", "?")
    role = node.get("role", "?")
    name = node.get("name", "")
    value = node.get("value")
    line = f'{ref} {role} "{name}"'
    if value is not None and value != "":
        line += f' value="{value}"'
    return line


def _print_nav_result(result: dict) -> None:
    """Print navigation result."""
    print(result.get("title", ""))
    print(result.get("url", ""))


# ── Error handling ────────────────────────────────────────────────

def _handle_tab_not_found(tab_id: str) -> str:
    """If the target tab doesn't exist, reset to tab0 and return it."""
    if tab_id != "tab0":
        _set_current_tab("tab0")
        print(f"Tab {tab_id} not found. Switched to tab0.", file=sys.stderr)
        return "tab0"
    raise


def _run(func, args: argparse.Namespace) -> int:
    """Run a command handler with standard error handling. Returns exit code."""
    try:
        func(args)
        return 0
    except AslanBrowserError as e:
        # Tab not found — reset and retry once
        if e.code == -32000 and "Tab not found" in e.message:
            tab = _current_tab(args)
            new_tab = _handle_tab_not_found(tab)
            if new_tab != tab:
                # Patch args and retry
                args.tab = new_tab
                try:
                    func(args)
                    return 0
                except AslanBrowserError as e2:
                    print(f"Error: {e2.message}", file=sys.stderr)
                    return 1
        print(f"Error: {e.message}", file=sys.stderr)
        return 1
    except ConnectionError as e:
        print(f"Error: {e}", file=sys.stderr)
        print("Is aslan-browser running?", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130


# ── Argument parser ───────────────────────────────────────────────

def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="aslan",
        description="Drive Aslan Browser from the command line.",
    )
    parser.add_argument("--version", action="version", version=f"aslan {__version__}")

    sub = parser.add_subparsers(dest="command")

    # ── status ────────────────────────────────────────────────────
    p = sub.add_parser("status", help="Check if Aslan Browser is running")
    p.set_defaults(func=cmd_status)

    # ── source ────────────────────────────────────────────────────
    p = sub.add_parser("source", help="Print SDK source path")
    p.set_defaults(func=cmd_source)

    # ── navigation ────────────────────────────────────────────────
    p = sub.add_parser("nav", help="Navigate to a URL")
    p.add_argument("url", help="URL to navigate to")
    p.add_argument("--wait", choices=["none", "load", "idle"], default="load",
                    help="Wait strategy (default: load)")
    p.add_argument("--timeout", type=int, default=30000, help="Timeout in ms")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_nav)

    p = sub.add_parser("back", help="Navigate back")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_back)

    p = sub.add_parser("forward", help="Navigate forward")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_forward)

    p = sub.add_parser("reload", help="Reload the page")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_reload)

    # ── reading ───────────────────────────────────────────────────
    p = sub.add_parser("tree", help="Print accessibility tree")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_tree)

    p = sub.add_parser("title", help="Print page title")
    p.add_argument("--tab", help="Target tab ID")
    p.set_defaults(func=cmd_title)

    p = sub.add_parser("url", help="Print current URL")
    p.add_argument("--tab", help="Target tab ID")
    p.set_defaults(func=cmd_url)

    p = sub.add_parser("text", help="Print page text content")
    p.add_argument("--chars", type=int, default=3000, help="Max characters (default: 3000)")
    p.add_argument("--tab", help="Target tab ID")
    p.set_defaults(func=cmd_text)

    p = sub.add_parser("html", help="Print page HTML")
    p.add_argument("--chars", type=int, default=20000, help="Max characters (default: 20000)")
    p.add_argument("--selector", help="Get innerHTML of a specific element instead of body")
    p.add_argument("--tab", help="Target tab ID")
    p.set_defaults(func=cmd_html)

    p = sub.add_parser("eval", help="Evaluate JavaScript")
    p.add_argument("script", help='JavaScript to evaluate (must use "return")')
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_eval)

    # ── interaction ───────────────────────────────────────────────
    p = sub.add_parser("click", help="Click an element")
    p.add_argument("target", help="@eN ref or CSS selector")
    p.add_argument("--tab", help="Target tab ID")
    p.set_defaults(func=cmd_click)

    p = sub.add_parser("fill", help="Fill an input field")
    p.add_argument("target", help="@eN ref or CSS selector")
    p.add_argument("value", help="Value to fill")
    p.add_argument("--tab", help="Target tab ID")
    p.set_defaults(func=cmd_fill)

    p = sub.add_parser("type", help="Type text into any field (works on contenteditable)")
    p.add_argument("target", help="@eN ref or CSS selector")
    p.add_argument("value", help="Text to type")
    p.add_argument("--tab", help="Target tab ID")
    p.set_defaults(func=cmd_type)

    p = sub.add_parser("select", help="Select a dropdown option")
    p.add_argument("target", help="@eN ref or CSS selector")
    p.add_argument("value", help="Option value to select")
    p.add_argument("--tab", help="Target tab ID")
    p.set_defaults(func=cmd_select)

    p = sub.add_parser("key", help="Send a keypress")
    p.add_argument("key_name", metavar="key", help="Key name: Enter, Tab, a, etc.")
    p.add_argument("--meta", action="store_true", help="Hold Cmd/Meta")
    p.add_argument("--ctrl", action="store_true", help="Hold Control")
    p.add_argument("--shift", action="store_true", help="Hold Shift")
    p.add_argument("--alt", action="store_true", help="Hold Alt/Option")
    p.add_argument("--tab", help="Target tab ID")
    p.set_defaults(func=cmd_key)

    p = sub.add_parser("scroll", help="Scroll the page")
    p.add_argument("--down", type=int, metavar="PX", help="Scroll down by pixels")
    p.add_argument("--up", type=int, metavar="PX", help="Scroll up by pixels")
    p.add_argument("--to", metavar="REF", help="Scroll element into view (@eN or CSS)")
    p.add_argument("--tab", help="Target tab ID")
    p.set_defaults(func=cmd_scroll)

    # ── wait ──────────────────────────────────────────────────────
    p = sub.add_parser("wait", help="Wait for page to reach a readiness state")
    p.add_argument("--idle", action="store_true", help="Wait for network idle + DOM stable")
    p.add_argument("--load", action="store_true", help="Wait for page load")
    p.add_argument("--timeout", type=int, default=10000, help="Timeout in ms (default: 10000)")
    p.add_argument("--tab", help="Target tab ID")
    p.set_defaults(func=cmd_wait)

    # ── file upload ────────────────────────────────────────────────
    p = sub.add_parser("upload", help="Upload a file to an input[type=file]")
    p.add_argument("file", help="Path to file to upload")
    p.add_argument("--selector", default='input[type="file"]',
                    help='CSS selector for file input (default: input[type="file"])')
    p.add_argument("--name", help="Override filename sent to the page")
    p.add_argument("--tab", help="Target tab ID")
    p.set_defaults(func=cmd_upload)

    # ── screenshots ───────────────────────────────────────────────
    p = sub.add_parser("shot", help="Take a screenshot")
    p.add_argument("path", nargs="?", default="/tmp/aslan-screenshot.jpg",
                    help="Output file path (default: /tmp/aslan-screenshot.jpg)")
    p.add_argument("--quality", type=int, default=70, help="JPEG quality 0-100 (default: 70)")
    p.add_argument("--width", type=int, default=1440, help="Viewport width (default: 1440)")
    p.add_argument("--tab", help="Target tab ID")
    p.set_defaults(func=cmd_shot)

    # ── tab management ────────────────────────────────────────────
    p = sub.add_parser("tabs", help="List all open tabs")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_tabs)

    p = sub.add_parser("tab:new", help="Create a new tab and switch to it")
    p.add_argument("url", nargs="?", help="URL to navigate to")
    p.add_argument("--hidden", action="store_true", help="Create hidden tab")
    p.add_argument("--width", type=int, default=1440)
    p.add_argument("--height", type=int, default=900)
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_tab_new)

    p = sub.add_parser("tab:close", help="Close a tab")
    p.add_argument("tab_id", nargs="?", help="Tab ID to close (default: current tab)")
    p.set_defaults(func=cmd_tab_close)

    p = sub.add_parser("tab:use", help="Switch the current tab")
    p.add_argument("tab_id", help="Tab ID to switch to")
    p.set_defaults(func=cmd_tab_use)

    p = sub.add_parser("tab:wait", help="Wait for a CSS selector to appear")
    p.add_argument("selector", help="CSS selector to wait for")
    p.add_argument("--timeout", type=int, default=5000, help="Timeout in ms (default: 5000)")
    p.add_argument("--tab", help="Target tab ID")
    p.set_defaults(func=cmd_tab_wait)

    # ── learn mode ────────────────────────────────────────────────
    p = sub.add_parser("learn:start", help="Start learn mode recording")
    p.add_argument("name", help="Recording name (e.g., reddit-create-post)")
    p.set_defaults(func=cmd_learn_start)

    p = sub.add_parser("learn:stop", help="Stop learn mode recording")
    p.add_argument("--json", action="store_true", dest="json_output",
                    help="Output full action log as JSON")
    p.set_defaults(func=cmd_learn_stop)

    p = sub.add_parser("learn:status", help="Check learn mode status")
    p.set_defaults(func=cmd_learn_status)

    # ── cookies ───────────────────────────────────────────────────
    p = sub.add_parser("cookies", help="Get cookies")
    p.add_argument("--url", help="Filter by URL")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_cookies)

    p = sub.add_parser("set-cookie", help="Set a cookie")
    p.add_argument("name", help="Cookie name")
    p.add_argument("value", help="Cookie value")
    p.add_argument("domain", help="Cookie domain (e.g. .example.com)")
    p.add_argument("--path", default="/", help="Cookie path (default: /)")
    p.add_argument("--expires", type=float, help="Expiry as Unix timestamp")
    p.add_argument("--tab", help="Target tab ID")
    p.set_defaults(func=cmd_set_cookie)

    return parser


# ── Commands ──────────────────────────────────────────────────────

# ── status / source ───────────────────────────────────────────────

def cmd_status(args: argparse.Namespace) -> None:
    """Check connection status."""
    state = _load_state()
    try:
        b = _connect()
        tabs = b.tab_list()
        b.close()
        current = state.get("tab", "tab0")
        print(f"Connected to /tmp/aslan-browser.sock")
        print(f"Current tab: {current}")
        print(f"Open tabs: {len(tabs)}")
    except ConnectionError as e:
        print(f"Not connected: {e}")
        sys.exit(1)


def cmd_source(args: argparse.Namespace) -> None:
    """Print SDK source path."""
    import aslan_browser
    print(os.path.dirname(os.path.abspath(aslan_browser.__file__)))


# ── navigation ────────────────────────────────────────────────────

def cmd_nav(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        result = b.navigate(args.url, tab_id=tab, wait_until=args.wait, timeout=args.timeout)
        if getattr(args, "json_output", False):
            _print_json(result)
        else:
            _print_nav_result(result)
    finally:
        b.close()


def cmd_back(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        result = b.go_back(tab_id=tab)
        if getattr(args, "json_output", False):
            _print_json(result)
        else:
            _print_nav_result(result)
    finally:
        b.close()


def cmd_forward(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        result = b.go_forward(tab_id=tab)
        if getattr(args, "json_output", False):
            _print_json(result)
        else:
            _print_nav_result(result)
    finally:
        b.close()


def cmd_reload(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        result = b.reload(tab_id=tab)
        if getattr(args, "json_output", False):
            _print_json(result)
        else:
            _print_nav_result(result)
    finally:
        b.close()


# ── reading ───────────────────────────────────────────────────────

def cmd_tree(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        tree = b.get_accessibility_tree(tab_id=tab)
        if getattr(args, "json_output", False):
            _print_json(tree)
        else:
            for node in tree:
                print(_format_tree_node(node))
    finally:
        b.close()


def cmd_title(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        print(b.get_title(tab_id=tab))
    finally:
        b.close()


def cmd_url(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        print(b.get_url(tab_id=tab))
    finally:
        b.close()


def cmd_text(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        text = b.evaluate(
            f"return document.body.innerText.substring(0, {args.chars})",
            tab_id=tab,
        )
        print(text or "")
    finally:
        b.close()


def cmd_html(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        if args.selector:
            js = f'var el = document.querySelector(sel); return el ? el.innerHTML.substring(0, {args.chars}) : "error: not found"'
            html = b.evaluate(js, tab_id=tab, args={"sel": args.selector})
        else:
            html = b.evaluate(
                f"return document.body.innerHTML.substring(0, {args.chars})",
                tab_id=tab,
            )
        print(html or "")
    finally:
        b.close()


def cmd_eval(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        result = b.evaluate(args.script, tab_id=tab)
        if getattr(args, "json_output", False):
            _print_json(result)
        else:
            if result is not None:
                print(result)
    finally:
        b.close()


# ── interaction ───────────────────────────────────────────────────

def cmd_click(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        b.click(args.target, tab_id=tab)
        print("ok")
    finally:
        b.close()


def cmd_fill(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        b.fill(args.target, args.value, tab_id=tab)
        print("ok")
    finally:
        b.close()


def cmd_type(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        # Resolve @eN refs to CSS selector
        target = args.target
        if target.startswith("@e"):
            target = f'[data-agent-ref="{target}"]'

        js = """
        var el = document.querySelector(sel);
        if (!el) return "error: element not found";
        el.focus();
        if (el.isContentEditable || el.getAttribute("contenteditable") === "true") {
            document.execCommand("insertText", false, text);
            return "typed (contenteditable)";
        } else if (el.tagName === "INPUT" || el.tagName === "TEXTAREA") {
            el.value = text;
            el.dispatchEvent(new Event("input", { bubbles: true }));
            el.dispatchEvent(new Event("change", { bubbles: true }));
            return "typed (input)";
        } else {
            el.focus();
            document.execCommand("insertText", false, text);
            return "typed (execCommand fallback)";
        }
        """
        result = b.evaluate(js, tab_id=tab, args={"sel": target, "text": args.value})
        print(result or "ok")
    finally:
        b.close()


def cmd_select(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        b.select(args.target, args.value, tab_id=tab)
        print("ok")
    finally:
        b.close()


def cmd_key(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    modifiers = {}
    if args.meta:
        modifiers["meta"] = True
    if args.ctrl:
        modifiers["ctrlKey"] = True
    if args.shift:
        modifiers["shiftKey"] = True
    if args.alt:
        modifiers["altKey"] = True
    b = _connect()
    try:
        b.keypress(args.key_name, tab_id=tab, modifiers=modifiers or None)
        print("ok")
    finally:
        b.close()


def cmd_scroll(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        if args.to:
            b.scroll(target=args.to, tab_id=tab)
        elif args.up:
            b.scroll(y=-args.up, tab_id=tab)
        elif args.down:
            b.scroll(y=args.down, tab_id=tab)
        else:
            b.scroll(y=500, tab_id=tab)  # default: scroll down 500px
        print("ok")
    finally:
        b.close()


# ── wait ──────────────────────────────────────────────────────────

def cmd_wait(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        if args.idle:
            # Navigate to the current URL with wait_until=idle to trigger idle wait
            # This uses the browser's built-in readiness detection
            url = b.get_url(tab_id=tab)
            js = """
            return await new Promise(function(resolve) {
                if (window.__agent && window.__agent._networkIdle && window.__agent._domStable) {
                    resolve("ready");
                    return;
                }
                var start = Date.now();
                var check = setInterval(function() {
                    var idle = !window.__agent || (window.__agent._networkIdle !== false);
                    var stable = !window.__agent || (window.__agent._domStable !== false);
                    if (idle && stable) {
                        clearInterval(check);
                        resolve("ready");
                    } else if (Date.now() - start > timeout) {
                        clearInterval(check);
                        resolve("timeout");
                    }
                }, 100);
            });
            """
            result = b.evaluate(js, tab_id=tab, args={"timeout": args.timeout})
            print(result or "ready")
        elif args.load:
            js = """
            return await new Promise(function(resolve) {
                if (document.readyState === "complete") {
                    resolve("ready");
                    return;
                }
                var start = Date.now();
                var check = setInterval(function() {
                    if (document.readyState === "complete") {
                        clearInterval(check);
                        resolve("ready");
                    } else if (Date.now() - start > timeout) {
                        clearInterval(check);
                        resolve("timeout");
                    }
                }, 100);
            });
            """
            result = b.evaluate(js, tab_id=tab, args={"timeout": args.timeout})
            print(result or "ready")
        else:
            # Default: wait for idle
            print("Usage: aslan wait --idle or aslan wait --load", file=sys.stderr)
            sys.exit(1)
    finally:
        b.close()


# ── file upload ───────────────────────────────────────────────────

def cmd_upload(args: argparse.Namespace) -> None:
    import base64
    import mimetypes

    filepath = os.path.abspath(args.file)
    if not os.path.exists(filepath):
        print(f"Error: file not found: {filepath}", file=sys.stderr)
        sys.exit(1)

    filename = args.name or os.path.basename(filepath)
    mimetype = mimetypes.guess_type(filepath)[0] or "application/octet-stream"

    with open(filepath, "rb") as f:
        b64data = base64.b64encode(f.read()).decode()

    tab = _current_tab(args)
    selector = args.selector

    js = """
    var input = document.querySelector(sel);
    if (!input) return "error: no element matches selector";
    var binary = atob(b64data);
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    var file = new File([bytes], fname, { type: mime });
    var dt = new DataTransfer();
    dt.items.add(file);
    input.files = dt.files;
    input.dispatchEvent(new Event("change", { bubbles: true }));
    return "uploaded " + fname + " (" + file.size + " bytes)";
    """

    b = _connect()
    try:
        result = b.evaluate(
            js, tab_id=tab,
            args={"sel": selector, "b64data": b64data, "fname": filename, "mime": mimetype},
        )
        print(result or "ok")
    finally:
        b.close()


# ── screenshots ───────────────────────────────────────────────────

def cmd_shot(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        size = b.save_screenshot(args.path, tab_id=tab, quality=args.quality, width=args.width)
        print(f"{args.path} ({size} bytes)")
    finally:
        b.close()


# ── tab management ────────────────────────────────────────────────

def cmd_tabs(args: argparse.Namespace) -> None:
    b = _connect()
    try:
        tabs = b.tab_list()
        current = _load_state().get("tab", "tab0")
        if getattr(args, "json_output", False):
            _print_json(tabs)
        else:
            for t in tabs:
                marker = "*" if t["tabId"] == current else " "
                tid = t["tabId"]
                url = t.get("url", "")
                title = t.get("title", "")
                print(f"{tid}{marker} {url}\t\"{title}\"")
    finally:
        b.close()


def cmd_tab_new(args: argparse.Namespace) -> None:
    b = _connect()
    try:
        params = {"width": args.width, "height": args.height}
        if args.url:
            params["url"] = args.url
        if args.hidden:
            params["hidden"] = True
        tab_id = b.tab_create(**params)
        _set_current_tab(tab_id)
        if getattr(args, "json_output", False):
            _print_json({"tabId": tab_id})
        else:
            print(tab_id)
    finally:
        b.close()


def cmd_tab_close(args: argparse.Namespace) -> None:
    tab = args.tab_id if args.tab_id else _load_state().get("tab", "tab0")
    b = _connect()
    try:
        b.tab_close(tab)
        # If we closed the current tab, switch to tab0
        state = _load_state()
        if state.get("tab") == tab:
            _set_current_tab("tab0")
            print(f"Closed {tab}. Switched to tab0.")
        else:
            print(f"Closed {tab}.")
    finally:
        b.close()


def cmd_tab_use(args: argparse.Namespace) -> None:
    # Verify the tab exists
    b = _connect()
    try:
        tabs = b.tab_list()
        tab_ids = [t["tabId"] for t in tabs]
        if args.tab_id not in tab_ids:
            print(f"Error: tab {args.tab_id} not found. Open tabs: {', '.join(tab_ids)}", file=sys.stderr)
            sys.exit(1)
        _set_current_tab(args.tab_id)
        print(f"Switched to {args.tab_id}")
    finally:
        b.close()


def cmd_tab_wait(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        b.wait_for_selector(args.selector, tab_id=tab, timeout=args.timeout)
        print("found")
    finally:
        b.close()


# ── learn mode ────────────────────────────────────────────────────

def cmd_learn_start(args: argparse.Namespace) -> None:
    b = _connect()
    try:
        result = b.learn_start(args.name)
        print(f"Recording: {args.name}")
        print(f"Screenshots: {result.get('screenshotDir', '')}")
    finally:
        b.close()


def cmd_learn_stop(args: argparse.Namespace) -> None:
    b = _connect()
    try:
        result = b.learn_stop()
        if getattr(args, "json_output", False):
            _print_json(result)
        else:
            name = result.get("name", "?")
            count = result.get("actionCount", 0)
            duration = result.get("duration", 0)
            print(f"Stopped: {name}")
            print(f"Actions: {count}")
            print(f"Duration: {duration / 1000:.1f}s")
            print(f"Screenshots: {result.get('screenshotDir', '')}")
    finally:
        b.close()


def cmd_learn_status(args: argparse.Namespace) -> None:
    b = _connect()
    try:
        result = b.learn_status()
        if result.get("recording"):
            print(f"Recording: {result.get('name', '?')} ({result.get('actionCount', 0)} actions)")
        else:
            print("Not recording")
    finally:
        b.close()


# ── cookies ───────────────────────────────────────────────────────

def cmd_cookies(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        cookies = b.get_cookies(tab_id=tab, url=getattr(args, "url", None))
        if getattr(args, "json_output", False):
            _print_json(cookies)
        else:
            for c in cookies:
                print(f"{c['name']}={c['value']}  domain={c['domain']}  path={c.get('path', '/')}")
    finally:
        b.close()


def cmd_set_cookie(args: argparse.Namespace) -> None:
    tab = _current_tab(args)
    b = _connect()
    try:
        b.set_cookie(
            args.name, args.value, args.domain,
            path=args.path, expires=args.expires, tab_id=tab,
        )
        print("ok")
    finally:
        b.close()


# ── Entry point ───────────────────────────────────────────────────

def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(0)

    if hasattr(args, "func"):
        code = _run(args.func, args)
        sys.exit(code)
    else:
        parser.print_help()
        sys.exit(0)


if __name__ == "__main__":
    main()
