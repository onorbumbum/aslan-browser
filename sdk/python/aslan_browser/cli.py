"""Aslan Browser CLI — drive the browser from the command line."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import sys
from typing import Any, Optional

from aslan_browser import __version__
from aslan_browser.client import AslanBrowser, AslanBrowserError

_DEFAULT_STATE_FILE = "/tmp/aslan-cli.json"
_DEFAULT_SHOT_PATH = "/tmp/aslan-screenshot.jpg"


# ── State management ──────────────────────────────────────────────

def _safe_session_name(name: str) -> str:
    """Return a filesystem-safe session name for per-session CLI state."""
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "-", name).strip(".-")
    return safe or "session"


def _session_name(args: Optional[argparse.Namespace] = None) -> Optional[str]:
    """Resolve requested session name from --session or ASLAN_SESSION."""
    if args is not None and hasattr(args, "session") and args.session:
        return args.session
    return os.environ.get("ASLAN_SESSION")


def _state_file(session_name: Optional[str] = None) -> str:
    """State file path. ASLAN_SESSION gets isolated current-tab state."""
    explicit = os.environ.get("ASLAN_STATE_FILE")
    if explicit:
        return explicit
    effective_session = session_name or os.environ.get("ASLAN_SESSION")
    if effective_session:
        return f"/tmp/aslan-cli-session-{_safe_session_name(effective_session)}.json"
    return _DEFAULT_STATE_FILE


def _load_state(session_name: Optional[str] = None) -> dict:
    """Load CLI state from disk. Creates default if missing."""
    state_file = _state_file(session_name)
    if os.path.exists(state_file):
        try:
            with open(state_file) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    state: dict[str, Any] = {"tab": "tab0"}
    if session_name:
        state["session_name"] = session_name
    return state


def _save_state(state: dict, session_name: Optional[str] = None) -> None:
    """Write CLI state to disk."""
    with open(_state_file(session_name), "w") as f:
        json.dump(state, f)


def _resolve_session_id(browser: AslanBrowser, session_name_or_id: str, *, create: bool = True) -> str:
    """Resolve a session by ID or name; create named sessions on demand."""
    sessions = browser.session_list()
    for session in sessions:
        if session.get("sessionId") == session_name_or_id or session.get("name") == session_name_or_id:
            return session["sessionId"]
    if create:
        return browser.session_get_or_create(session_name_or_id)
    raise AslanBrowserError(-32004, f"Session not found: {session_name_or_id}")


def _current_tab(args: argparse.Namespace) -> str:
    """Resolve the target tab: explicit --tab, session current tab, or default state."""
    if hasattr(args, "tab") and args.tab:
        return args.tab

    session_name = _session_name(args)
    if session_name:
        b = _connect()
        try:
            session_id = _resolve_session_id(b, session_name, create=True)
            state = _load_state(session_name)
            current = state.get("tab")
            tabs = b.tab_list(session_id=session_id)
            tab_ids = [t["tabId"] for t in tabs]
            if current in tab_ids:
                return current
            if tab_ids:
                current = tab_ids[0]
            else:
                current = b.tab_create(session_id=session_id)
            _set_current_tab(current, session_name=session_name, session_id=session_id)
            return current
        finally:
            b.close()

    return _load_state().get("tab", "tab0")


def _set_current_tab(tab_id: str, session_name: Optional[str] = None, session_id: Optional[str] = None) -> None:
    """Update the current tab in the matching state file."""
    effective_session = session_name or os.environ.get("ASLAN_SESSION")
    state = _load_state(effective_session)
    state["tab"] = tab_id
    if effective_session:
        state["session_name"] = effective_session
    if session_id:
        state["session_id"] = session_id
    _save_state(state, effective_session)


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
    p.add_argument("--session", help="Target session name or ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_nav)

    p = sub.add_parser("back", help="Navigate back")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_back)

    p = sub.add_parser("forward", help="Navigate forward")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_forward)

    p = sub.add_parser("reload", help="Reload the page")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_reload)

    # ── reading ───────────────────────────────────────────────────
    p = sub.add_parser("tree", help="Print accessibility tree")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_tree)

    p = sub.add_parser("title", help="Print page title")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.set_defaults(func=cmd_title)

    p = sub.add_parser("url", help="Print current URL")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.set_defaults(func=cmd_url)

    p = sub.add_parser("text", help="Print page text content")
    p.add_argument("--chars", type=int, default=3000, help="Max characters (default: 3000)")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.set_defaults(func=cmd_text)

    p = sub.add_parser("html", help="Print page HTML")
    p.add_argument("--chars", type=int, default=20000, help="Max characters (default: 20000)")
    p.add_argument("--selector", help="Get innerHTML of a specific element instead of body")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.set_defaults(func=cmd_html)

    p = sub.add_parser("eval", help="Evaluate JavaScript")
    p.add_argument("script", help='JavaScript to evaluate (must use "return")')
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_eval)

    # ── interaction ───────────────────────────────────────────────
    p = sub.add_parser("click", help="Click an element")
    p.add_argument("target", help="@eN ref or CSS selector")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.set_defaults(func=cmd_click)

    p = sub.add_parser("fill", help="Fill an input field")
    p.add_argument("target", help="@eN ref or CSS selector")
    p.add_argument("value", help="Value to fill")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.set_defaults(func=cmd_fill)

    p = sub.add_parser("type", help="Type text into any field (works on contenteditable)")
    p.add_argument("target", help="@eN ref or CSS selector")
    p.add_argument("value", help="Text to type")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.set_defaults(func=cmd_type)

    p = sub.add_parser("select", help="Select a dropdown option")
    p.add_argument("target", help="@eN ref or CSS selector")
    p.add_argument("value", help="Option value to select")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.set_defaults(func=cmd_select)

    p = sub.add_parser("key", help="Send a keypress")
    p.add_argument("key_name", metavar="key", help="Key name: Enter, Tab, a, etc.")
    p.add_argument("--meta", action="store_true", help="Hold Cmd/Meta")
    p.add_argument("--ctrl", action="store_true", help="Hold Control")
    p.add_argument("--shift", action="store_true", help="Hold Shift")
    p.add_argument("--alt", action="store_true", help="Hold Alt/Option")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.set_defaults(func=cmd_key)

    p = sub.add_parser("scroll", help="Scroll the page")
    p.add_argument("--down", type=int, metavar="PX", help="Scroll down by pixels")
    p.add_argument("--up", type=int, metavar="PX", help="Scroll up by pixels")
    p.add_argument("--to", metavar="REF", help="Scroll element into view (@eN or CSS)")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.set_defaults(func=cmd_scroll)

    # ── wait ──────────────────────────────────────────────────────
    p = sub.add_parser("wait", help="Wait for page to reach a readiness state")
    p.add_argument("--idle", action="store_true", help="Wait for network idle + DOM stable")
    p.add_argument("--load", action="store_true", help="Wait for page load")
    p.add_argument("--timeout", type=int, default=10000, help="Timeout in ms (default: 10000)")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.set_defaults(func=cmd_wait)

    # ── file upload ────────────────────────────────────────────────
    p = sub.add_parser("upload", help="Upload a file to an input[type=file]")
    p.add_argument("file", help="Path to file to upload")
    p.add_argument("--selector", default='input[type="file"]',
                    help='CSS selector for file input (default: input[type="file"])')
    p.add_argument("--name", help="Override filename sent to the page")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.set_defaults(func=cmd_upload)

    # ── screenshots ───────────────────────────────────────────────
    p = sub.add_parser(
        "shot",
        help="Take a screenshot of a URL or the current tab",
        description=(
            "aslan shot [URL] [PATH] — with a URL, opens a temporary hidden tab, "
            "loads it, captures and closes it. Without a URL, captures the current tab. "
            "PATH extension picks the format: .png or .jpg/.jpeg."
        ),
    )
    p.add_argument("target", nargs="*", metavar="[URL] [PATH]",
                    help="Optional URL (http/https/file/about), then output path "
                         f"(default: {_DEFAULT_SHOT_PATH})")
    p.add_argument("--quality", type=int, default=70, help="JPEG quality 0-100 (default: 70)")
    p.add_argument("--width", type=int, default=None,
                    help="Viewport width in px (URL default: 1280)")
    size = p.add_mutually_exclusive_group()
    size.add_argument("--height", type=int, default=None,
                       help="Viewport height in px (URL default: 720); single frame only")
    size.add_argument("--full-page", action="store_true", dest="full_page",
                       help="Capture the whole page at --width (scroll-and-stitch; height comes from the page)")
    p.add_argument("--tab", help="Target tab ID (current-tab mode)")
    p.add_argument("--session", help="Target session name or ID")
    p.set_defaults(func=cmd_shot)

    # ── tab management ────────────────────────────────────────────
    p = sub.add_parser("tabs", help="List all open tabs")
    p.add_argument("--session", help="Filter by session name or ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_tabs)

    p = sub.add_parser("tab:new", help="Create a new tab and switch to it")
    p.add_argument("url", nargs="?", help="URL to navigate to")
    p.add_argument("--hidden", action="store_true", help="Create hidden tab")
    p.add_argument("--width", type=int, default=1440)
    p.add_argument("--height", type=int, default=900)
    p.add_argument("--session", help="Create tab in session name or ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_tab_new)

    p = sub.add_parser("tab:close", help="Close a tab")
    p.add_argument("tab_id", nargs="?", help="Tab ID to close (default: current tab)")
    p.add_argument("--session", help="Use current tab from session name or ID")
    p.set_defaults(func=cmd_tab_close)

    p = sub.add_parser("tab:use", help="Switch the current tab")
    p.add_argument("tab_id", help="Tab ID to switch to")
    p.add_argument("--session", help="Set current tab for session name or ID")
    p.set_defaults(func=cmd_tab_use)

    p = sub.add_parser("tab:wait", help="Wait for a CSS selector to appear")
    p.add_argument("selector", help="CSS selector to wait for")
    p.add_argument("--timeout", type=int, default=5000, help="Timeout in ms (default: 5000)")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
    p.set_defaults(func=cmd_tab_wait)

    # ── session management ────────────────────────────────────────
    p = sub.add_parser("sessions", help="List sessions")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_sessions)

    p = sub.add_parser("session:create", help="Create a new named session")
    p.add_argument("name", help="Session name")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_session_create)

    p = sub.add_parser("session:use", help="Create/find a named session and print usage info")
    p.add_argument("name", help="Session name")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.add_argument("--shell", action="store_true", help="Print shell export command")
    p.set_defaults(func=cmd_session_use)

    p = sub.add_parser("session:destroy", help="Destroy a session by name or ID and close its tabs")
    p.add_argument("name", help="Session name or ID")
    p.set_defaults(func=cmd_session_destroy)

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
    p.add_argument("--session", help="Target session name or ID")
    p.add_argument("--json", action="store_true", dest="json_output")
    p.set_defaults(func=cmd_cookies)

    p = sub.add_parser("set-cookie", help="Set a cookie")
    p.add_argument("name", help="Cookie name")
    p.add_argument("value", help="Cookie value")
    p.add_argument("domain", help="Cookie domain (e.g. .example.com)")
    p.add_argument("--path", default="/", help="Cookie path (default: /)")
    p.add_argument("--expires", type=float, help="Expiry as Unix timestamp")
    p.add_argument("--tab", help="Target tab ID")
    p.add_argument("--session", help="Target session name or ID")
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

_URL_RE = re.compile(r"^(https?|file|about):", re.IGNORECASE)
_SHOT_FORMATS = {".png": "png", ".jpg": "jpeg", ".jpeg": "jpeg"}
_URL_MODE_VIEWPORT = (1280, 720)
_MAX_FULL_PAGE_HEIGHT = 16384


def _shot_target(args: argparse.Namespace) -> tuple[Optional[str], str, str]:
    """Split `shot` positionals into (url, path, format); exit on bad input."""
    items = list(args.target)
    url = items.pop(0) if items and _URL_RE.match(items[0]) else None
    if len(items) > 1:
        sys.exit(f"Error: unexpected arguments: {' '.join(items[1:])}")
    path = items[0] if items else _DEFAULT_SHOT_PATH
    fmt = _SHOT_FORMATS.get(os.path.splitext(path)[1].lower())
    if fmt is None:
        sys.exit(f"Error: unsupported screenshot extension in '{path}' (use .png, .jpg or .jpeg)")
    return url, path, fmt


def cmd_shot(args: argparse.Namespace) -> None:
    url, path, fmt = _shot_target(args)
    opts: dict[str, Any] = {"quality": args.quality, "format": fmt, "full_page": args.full_page}

    if url:
        width = args.width or _URL_MODE_VIEWPORT[0]
        opts["viewport_width"] = width
        if not args.full_page:
            opts["viewport_height"] = args.height or _URL_MODE_VIEWPORT[1]
        _shot_url(args, url, path, width, opts)
        return

    # Current-tab mode: only resize when asked; otherwise keep the legacy capture.
    if args.width is not None:
        opts["viewport_width"] = args.width
    if args.height is not None:
        opts["viewport_height"] = args.height
    tab = _current_tab(args)
    b = _connect()
    try:
        size = b.save_screenshot(path, tab_id=tab, **opts)
        print(f"{path} ({size} bytes)")
        _warn_if_truncated(b, tab, args.full_page)
    finally:
        b.close()


def _shot_url(args: argparse.Namespace, url: str, path: str, width: int, opts: dict) -> None:
    """Load `url` in a throwaway hidden tab, capture it, and always close the tab."""
    session_name = _session_name(args)
    b = _connect()
    tab = None
    try:
        session_id = _resolve_session_id(b, session_name, create=True) if session_name else None
        height = opts.get("viewport_height", _URL_MODE_VIEWPORT[1])
        tab = b.tab_create(width=width, height=height, hidden=True, session_id=session_id)
        b.navigate(url, tab_id=tab)
        size = b.save_screenshot(path, tab_id=tab, **opts)
        print(f"{path} ({size} bytes)")
        _warn_if_truncated(b, tab, args.full_page)
    finally:
        if tab:
            try:
                b.tab_close(tab)
            except AslanBrowserError:
                pass
        b.close()


def _warn_if_truncated(b: AslanBrowser, tab: str, full_page: bool) -> None:
    """Tell the user when a full-page capture was clipped at the height cap."""
    if not full_page:
        return
    height = b.evaluate("return document.documentElement.scrollHeight", tab_id=tab)
    if isinstance(height, (int, float)) and height > _MAX_FULL_PAGE_HEIGHT:
        print(
            f"Warning: page is {int(height)}px tall; capture clipped at {_MAX_FULL_PAGE_HEIGHT}px",
            file=sys.stderr,
        )


# ── tab management ────────────────────────────────────────────────

def cmd_tabs(args: argparse.Namespace) -> None:
    session_name = _session_name(args)
    b = _connect()
    try:
        session_id = _resolve_session_id(b, session_name, create=True) if session_name else None
        tabs = b.tab_list(session_id=session_id)
        current = _load_state(session_name).get("tab", "tab0")
        if getattr(args, "json_output", False):
            _print_json(tabs)
        else:
            for t in tabs:
                marker = "*" if t["tabId"] == current else " "
                tid = t["tabId"]
                url = t.get("url", "")
                title = t.get("title", "")
                session = t.get("sessionName") or t.get("sessionId") or ""
                suffix = f" [{session}]" if session else ""
                print(f"{tid}{marker} {url}\t\"{title}\"{suffix}")
    finally:
        b.close()


def cmd_tab_new(args: argparse.Namespace) -> None:
    session_name = _session_name(args)
    b = _connect()
    try:
        session_id = _resolve_session_id(b, session_name, create=True) if session_name else None
        params = {"width": args.width, "height": args.height}
        if args.url:
            params["url"] = args.url
        if args.hidden:
            params["hidden"] = True
        if session_id:
            params["session_id"] = session_id
        tab_id = b.tab_create(**params)
        _set_current_tab(tab_id, session_name=session_name, session_id=session_id)
        if getattr(args, "json_output", False):
            result = {"tabId": tab_id}
            if session_id:
                result["sessionId"] = session_id
                result["sessionName"] = session_name
            _print_json(result)
        else:
            print(tab_id)
    finally:
        b.close()


def cmd_tab_close(args: argparse.Namespace) -> None:
    session_name = _session_name(args)
    tab = args.tab_id if args.tab_id else _load_state(session_name).get("tab", "tab0")
    b = _connect()
    try:
        session_id = _resolve_session_id(b, session_name, create=False) if session_name else None
        b.tab_close(tab)
        state = _load_state(session_name)
        if state.get("tab") == tab:
            remaining = b.tab_list(session_id=session_id) if session_id else b.tab_list()
            if remaining:
                new_current = remaining[0]["tabId"]
                _set_current_tab(new_current, session_name=session_name, session_id=session_id)
                print(f"Closed {tab}. Switched to {new_current}.")
            else:
                state.pop("tab", None)
                if session_name:
                    state["session_name"] = session_name
                if session_id:
                    state["session_id"] = session_id
                _save_state(state, session_name)
                print(f"Closed {tab}.")
        else:
            print(f"Closed {tab}.")
    finally:
        b.close()


def cmd_tab_use(args: argparse.Namespace) -> None:
    session_name = _session_name(args)
    b = _connect()
    try:
        session_id = _resolve_session_id(b, session_name, create=False) if session_name else None
        tabs = b.tab_list(session_id=session_id)
        tab_ids = [t["tabId"] for t in tabs]
        if args.tab_id not in tab_ids:
            print(f"Error: tab {args.tab_id} not found. Open tabs: {', '.join(tab_ids)}", file=sys.stderr)
            sys.exit(1)
        _set_current_tab(args.tab_id, session_name=session_name, session_id=session_id)
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


# ── session management ────────────────────────────────────────────

def cmd_sessions(args: argparse.Namespace) -> None:
    b = _connect()
    try:
        sessions = b.session_list()
        if getattr(args, "json_output", False):
            _print_json(sessions)
        else:
            for s in sessions:
                sid = s.get("sessionId", "")
                name = s.get("name", "")
                tab_count = s.get("tabCount", 0)
                print(f"{sid}\t{name}\t{tab_count} tabs")
    finally:
        b.close()


def cmd_session_create(args: argparse.Namespace) -> None:
    b = _connect()
    try:
        session_id = b.session_create(args.name)
        if getattr(args, "json_output", False):
            _print_json({"sessionId": session_id, "name": args.name})
        else:
            print(session_id)
    finally:
        b.close()


def cmd_session_use(args: argparse.Namespace) -> None:
    b = _connect()
    try:
        session_id = b.session_get_or_create(args.name)
        _save_state({"session_name": args.name, "session_id": session_id}, args.name)
        if getattr(args, "json_output", False):
            _print_json({
                "sessionId": session_id,
                "name": args.name,
                "stateFile": _state_file(args.name),
                "export": f"export ASLAN_SESSION={shlex.quote(args.name)}",
            })
        elif args.shell:
            print(f"export ASLAN_SESSION={shlex.quote(args.name)}")
        else:
            print(f"Using session {args.name} ({session_id})")
            print(f"State file: {_state_file(args.name)}")
            print(f"Run: export ASLAN_SESSION={shlex.quote(args.name)}")
    finally:
        b.close()


def cmd_session_destroy(args: argparse.Namespace) -> None:
    b = _connect()
    try:
        closed = b.session_destroy(args.name)
        print(f"Destroyed {args.name}. Closed tabs: {', '.join(closed) if closed else 'none'}")
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
