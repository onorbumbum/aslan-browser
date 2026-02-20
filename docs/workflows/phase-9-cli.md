# Phase 9 — CLI: Token-Efficient Agent Interface

Replace Python-script-per-action with single-line bash commands. The CLI is a thin, zero-dependency wrapper around the existing Python SDK — installed as `aslan` on PATH. Each invocation connects, executes one operation, prints the result, and disconnects. A state file tracks the "current tab" across calls.

**State file:** `docs/workflows/state/phase-9-plan.json`
**Dependencies:** Phase 7 complete (SDK stable), Phase 8 complete (loading feedback)

---

## Context & Motivation

### The Problem

When an AI agent drives Aslan Browser via the skill, every interaction requires writing a Python heredoc:

```python
python3 << 'PYEOF'
from aslan_browser import AslanBrowser

with AslanBrowser() as b:
    tab = b.tab_create()
    b.navigate("https://example.com", tab_id=tab, wait_until="idle")
    tree = b.get_accessibility_tree(tab_id=tab)
    for node in tree:
        print(f"{node['ref']} {node['role']} \"{node['name']}\"")
PYEOF
```

That is ~200 tokens of boilerplate to navigate and read a page. The agent writes this pattern dozens of times per session — different URLs, different actions, but the same imports, context manager, tab management, and output formatting every time.

Additionally, the skill document (`SKILL.md` + `SDK_REFERENCE.md` + `core.md`) is ~5,000 tokens of context that teaches the agent how to use the Python SDK. Most of that instruction disappears with a CLI.

### The Solution

A CLI where the same operation is:

```bash
aslan nav https://example.com --wait idle
aslan tree
```

~30 tokens. **5-8x reduction per interaction.**

The CLI handles connection, tab resolution, output formatting, and error handling internally. The agent just calls commands.

### Design Principles

1. **One command = one action.** No multi-step scripts. The agent chains with `&&` or `;` in bash when needed.
2. **Current-tab model.** A state file (`/tmp/aslan-cli.json`) tracks the active tab. All commands target it by default. `--tab <id>` overrides.
3. **Compact output by default.** Tree prints one line per node. Screenshots save to file. JSON mode (`--json`) available for programmatic use.
4. **Zero new dependencies.** Pure Python, uses only the existing SDK (`aslan_browser`) and stdlib.
5. **Installed as `aslan` entry point.** `pip install -e sdk/python` puts `aslan` on PATH.

### Token Budget Comparison

| Task | Python SDK (tokens) | CLI (tokens) | Savings |
|---|---|---|---|
| Navigate + read tree | ~200 | ~30 | 85% |
| Click + read result | ~180 | ~20 | 89% |
| Fill + keypress Enter | ~170 | ~25 | 85% |
| Screenshot | ~150 | ~15 | 90% |
| Evaluate JS | ~160 | ~20 | 88% |
| Skill context (SKILL.md etc.) | ~5,000 | ~1,500 | 70% |

---

## CLI Command Reference

All commands connect with `auto_session=False` and target the current tab from the state file unless `--tab <id>` is passed.

### Global Flags (all commands)

| Flag | Description |
|---|---|
| `--tab <id>` | Target a specific tab instead of the current tab |
| `--json` | Output raw JSON instead of formatted text |

### Navigation

```bash
aslan nav <url> [--wait none|load|idle] [--timeout <ms>]
# Navigate to URL. Default wait=load. Prints: title and final URL.

aslan back
# Navigate back. Prints: title and URL.

aslan forward
# Navigate forward. Prints: title and URL.

aslan reload
# Reload the page. Prints: title and URL.
```

### Reading

```bash
aslan tree
# Print accessibility tree. One line per node:
# @e0 link "Show HN: Aslan Browser"
# @e1 textbox "Search" value=""
# @e2 button "Submit"

aslan title
# Print page title.

aslan url
# Print current URL.

aslan text [--chars <n>]
# Print page text (innerText). Default: first 3000 chars.

aslan eval <script>
# Evaluate JavaScript. Prints the return value.
# MUST include "return" — e.g.: aslan eval "return document.title"
```

### Interaction

```bash
aslan click <ref-or-selector>
# Click an element. @e3 or "button.submit"

aslan fill <ref-or-selector> <value>
# Fill an input field.

aslan select <ref-or-selector> <value>
# Select a dropdown option.

aslan key <key> [--meta] [--ctrl] [--shift] [--alt]
# Send a keypress. Key names: Enter, Tab, Escape, ArrowDown, a, b, etc.

aslan scroll [--down <px>] [--up <px>] [--to <ref-or-selector>]
# Scroll the page. Default: --down 500.
```

### Screenshots

```bash
aslan shot [<path>] [--quality <0-100>] [--width <px>]
# Take screenshot. Default path: /tmp/aslan-screenshot.jpg. Default quality: 70, width: 1440.
# Prints: saved file path and size.
```

### Tab Management

```bash
aslan tabs
# List all tabs. Marks the current tab with *.
# tab0  https://example.com     "Example Domain"
# tab1* https://google.com      "Google"

aslan tab:new [<url>] [--hidden] [--width <px>] [--height <px>]
# Create a new tab and switch to it. Optionally navigate to URL.
# Prints: new tab ID.

aslan tab:close [<id>]
# Close a tab. Default: current tab. Switches current to tab0 if current was closed.

aslan tab:use <id>
# Switch the current tab.

aslan tab:wait <selector> [--timeout <ms>]
# Wait for a CSS selector to appear. Default timeout: 5000ms.
```

### Cookies

```bash
aslan cookies [--url <url>]
# Get cookies. Optionally filter by URL.

aslan set-cookie <name> <value> <domain> [--path <p>] [--expires <timestamp>]
# Set a cookie.
```

### Status

```bash
aslan status
# Check if Aslan Browser is running and print connection info.
# Prints: connected/not connected, socket path, current tab.

aslan source
# Print the aslan-browser Python SDK source path (for agents that need to check installation).
```

### Output Formats

**Default (human-readable):**
```
$ aslan tree
@e0 link "Show HN: Aslan Browser"
@e1 textbox "Search" value=""
@e2 button "Submit"
@e3 heading "Top Stories"
@e4 link "Ask HN: What are you working on?"
```

**JSON mode (`--json`):**
```json
[
  {"ref": "@e0", "role": "link", "name": "Show HN: Aslan Browser", "tag": "A", "rect": {"x": 10, "y": 50, "w": 200, "h": 20}},
  ...
]
```

---

## State File

**Path:** `/tmp/aslan-cli.json`

**Schema:**
```json
{
  "tab": "tab0"
}
```

That's it. One field: the current tab ID. Created automatically on first CLI invocation if it doesn't exist.

**Rules:**
- `aslan tab:new` creates a tab and updates `tab` to the new ID.
- `aslan tab:use <id>` updates `tab`.
- `aslan tab:close` on the current tab resets `tab` to `"tab0"`.
- If a command targets a tab that no longer exists (server returns tab-not-found), reset `tab` to `"tab0"` and retry once.

---

## File Layout

```
sdk/python/
├── aslan_browser/
│   ├── __init__.py          # UPDATED: add CLI version info
│   ├── client.py            # unchanged
│   ├── async_client.py      # unchanged
│   └── cli.py               # NEW: CLI implementation (~400 lines)
├── pyproject.toml            # UPDATED: add [project.scripts] entry
├── SDK_REFERENCE.md          # unchanged (Python SDK docs stay)
└── CLI_REFERENCE.md          # NEW: agent-facing CLI cheat sheet (~150 lines)

skills/aslan-browser/
├── SKILL.md                  # REWRITTEN: teach CLI instead of Python SDK
├── SDK_REFERENCE.md          # REPLACED: symlink/copy of CLI_REFERENCE.md
└── knowledge/
    └── core.md               # UPDATED: CLI-specific operational rules
```

---

## Tools

### State Queries

```bash
# Get next pending work item ID
jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-9-plan.json | head -1

# Get full details of a specific work item
jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-9-plan.json

# Get progress summary
jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-9-plan.json
```

### State Mutations

```bash
# Mark item as done
jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-9-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-9-plan.json

# Mark item as error
jq --arg id "ITEM_ID" --arg err "Error description" '(.workItems[] | select(.id == $id)) |= . + {"status": "error", "errorMsg": $err}' docs/workflows/state/phase-9-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-9-plan.json
```

### Build & Verify

```bash
# Install/update the SDK + CLI entry point
cd sdk/python && pip install -e . && cd ../..

# Verify CLI is on PATH
aslan status

# Verify a command works (app must be running)
aslan nav https://example.com
aslan tree
aslan shot /tmp/test.jpg

# Run CLI tests
cd sdk/python && python3 -m pytest tests/test_cli.py -v && cd ../..
```

---

## Workflow

### 1. Setup (One-time)

1. Read configuration:
   ```bash
   jq '.metadata' docs/workflows/state/phase-9-plan.json
   ```
   Store: `projectRoot`, `sdkDir`, `skillDir`.

2. Read in full (parallel reads):
   - `docs/workflows/conventions.md`
   - `docs/workflows/notes.md`

3. Check progress:
   ```bash
   jq -r '.workItems | length as $total | [.[] | select(.status == "done")] | length as $done | "\($done)/\($total) complete"' docs/workflows/state/phase-9-plan.json
   ```

4. Read the existing SDK source files in full — the CLI wraps these:
   - `sdk/python/aslan_browser/__init__.py`
   - `sdk/python/aslan_browser/client.py`
   - `sdk/python/pyproject.toml`

   CRITICAL: Read the ENTIRE content of each file. The CLI delegates to `AslanBrowser` methods.

5. Read the existing skill files in full — these will be rewritten:
   - `skills/aslan-browser/SKILL.md`
   - `skills/aslan-browser/SDK_REFERENCE.md`
   - `skills/aslan-browser/knowledge/core.md`

### 2. Process Work Items (Repeat for each)

1. **Find next pending item:**
   ```bash
   jq -r '.workItems[] | select(.status == "pending") | .id' docs/workflows/state/phase-9-plan.json | head -1
   ```
   If no pending items remain, go to Completion.

2. **Load work item details:**
   ```bash
   jq --arg id "ITEM_ID" '.workItems[] | select(.id == $id)' docs/workflows/state/phase-9-plan.json
   ```

3. **Check dependencies.**
   Read the `dependsOn` array. For each dependency, verify its status is `"done"`:
   ```bash
   jq --arg id "DEP_ID" '.workItems[] | select(.id == $id) | .status' docs/workflows/state/phase-9-plan.json
   ```
   If any dependency is not done, skip this item and find the next pending item without unmet dependencies.

4. **Load context:**
   Re-read ALL files listed in `filesToModify` and `filesToCreate` (if they exist) in full.
   CRITICAL: Read the ENTIRE file. Do NOT rely on memory from the setup phase.

5. **Implement:**

   Follow the work item's `description` and the detailed implementation guidance below.

   ---

   #### Work Item: `cli-infrastructure`

   **Goal:** Create `sdk/python/aslan_browser/cli.py` with the argument parser, connection management, state file handling, output formatting, and entry point. No commands yet — just the skeleton that all commands plug into.

   **Create `sdk/python/aslan_browser/cli.py`:**

   ```python
   """Aslan Browser CLI — drive the browser from the command line."""

   from __future__ import annotations

   import argparse
   import json
   import os
   import sys
   from typing import Any, Optional

   from aslan_browser.client import AslanBrowser, AslanBrowserError

   _STATE_FILE = "/tmp/aslan-cli.json"
   _VERSION = "0.1.0"


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
       parser.add_argument("--version", action="version", version=f"aslan {_VERSION}")

       sub = parser.add_subparsers(dest="command")

       # status
       p = sub.add_parser("status", help="Check if Aslan Browser is running")
       p.set_defaults(func=cmd_status)

       # ── commands are added by subsequent work items ──
       # Each work item adds its sub.add_parser() block here.
       # The parser is built incrementally.

       return parser


   # ── Commands ──────────────────────────────────────────────────────

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
   ```

   **Update `sdk/python/pyproject.toml`** — add the console script entry point:

   ```toml
   [project.scripts]
   aslan = "aslan_browser.cli:main"
   ```

   Add this section after `[project.optional-dependencies]`.

   **Update `sdk/python/aslan_browser/__init__.py`** — add CLI version:

   No changes needed to `__init__.py` — the CLI imports from `client.py` directly. The `_VERSION` in `cli.py` is independent.

   **Verification:**
   ```bash
   cd sdk/python && pip install -e . && cd ../..
   aslan --version       # should print "aslan 0.1.0"
   aslan --help          # should show help with "status" subcommand
   aslan status          # should connect and print tab info (app must be running)
   ```

   DO NOT add any command besides `status` in this work item. Each command group is a separate work item.

   ---

   #### Work Item: `cmd-navigation`

   **Goal:** Add `nav`, `back`, `forward`, `reload` commands.

   **Add to `_build_parser()` in `cli.py`:**

   ```python
   # nav
   p = sub.add_parser("nav", help="Navigate to a URL")
   p.add_argument("url", help="URL to navigate to")
   p.add_argument("--wait", choices=["none", "load", "idle"], default="load",
                   help="Wait strategy (default: load)")
   p.add_argument("--timeout", type=int, default=30000, help="Timeout in ms")
   p.add_argument("--tab", help="Target tab ID")
   p.add_argument("--json", action="store_true", dest="json_output")
   p.set_defaults(func=cmd_nav)

   # back
   p = sub.add_parser("back", help="Navigate back")
   p.add_argument("--tab", help="Target tab ID")
   p.add_argument("--json", action="store_true", dest="json_output")
   p.set_defaults(func=cmd_back)

   # forward
   p = sub.add_parser("forward", help="Navigate forward")
   p.add_argument("--tab", help="Target tab ID")
   p.add_argument("--json", action="store_true", dest="json_output")
   p.set_defaults(func=cmd_forward)

   # reload
   p = sub.add_parser("reload", help="Reload the page")
   p.add_argument("--tab", help="Target tab ID")
   p.add_argument("--json", action="store_true", dest="json_output")
   p.set_defaults(func=cmd_reload)
   ```

   **Add command handlers:**

   ```python
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
   ```

   **Verification:**
   ```bash
   pip install -e sdk/python
   aslan nav https://example.com
   # Should print title and URL
   aslan nav https://example.com --json
   # Should print {"url": "...", "title": "..."}
   aslan back
   aslan forward
   aslan reload
   ```

   ---

   #### Work Item: `cmd-reading`

   **Goal:** Add `tree`, `title`, `url`, `text`, `eval` commands.

   **Add to `_build_parser()` in `cli.py`:**

   ```python
   # tree
   p = sub.add_parser("tree", help="Print accessibility tree")
   p.add_argument("--tab", help="Target tab ID")
   p.add_argument("--json", action="store_true", dest="json_output")
   p.set_defaults(func=cmd_tree)

   # title
   p = sub.add_parser("title", help="Print page title")
   p.add_argument("--tab", help="Target tab ID")
   p.set_defaults(func=cmd_title)

   # url
   p = sub.add_parser("url", help="Print current URL")
   p.add_argument("--tab", help="Target tab ID")
   p.set_defaults(func=cmd_url)

   # text
   p = sub.add_parser("text", help="Print page text content")
   p.add_argument("--chars", type=int, default=3000, help="Max characters (default: 3000)")
   p.add_argument("--tab", help="Target tab ID")
   p.set_defaults(func=cmd_text)

   # eval
   p = sub.add_parser("eval", help="Evaluate JavaScript")
   p.add_argument("script", help='JavaScript to evaluate (must use "return")')
   p.add_argument("--tab", help="Target tab ID")
   p.add_argument("--json", action="store_true", dest="json_output")
   p.set_defaults(func=cmd_eval)
   ```

   **Add command handlers:**

   ```python
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
   ```

   **Verification:**
   ```bash
   aslan nav https://example.com
   aslan tree
   # @e0 link "More information..."
   # @e1 heading "Example Domain"
   aslan tree --json
   # [{"ref": "@e0", ...}, ...]
   aslan title
   # Example Domain
   aslan url
   # https://example.com/
   aslan text --chars 200
   # Example Domain\nThis domain is for use in illustrative examples...
   aslan eval "return document.querySelectorAll('a').length"
   # 1
   ```

   ---

   #### Work Item: `cmd-interaction`

   **Goal:** Add `click`, `fill`, `select`, `key`, `scroll` commands.

   **Add to `_build_parser()` in `cli.py`:**

   ```python
   # click
   p = sub.add_parser("click", help="Click an element")
   p.add_argument("target", help="@eN ref or CSS selector")
   p.add_argument("--tab", help="Target tab ID")
   p.set_defaults(func=cmd_click)

   # fill
   p = sub.add_parser("fill", help="Fill an input field")
   p.add_argument("target", help="@eN ref or CSS selector")
   p.add_argument("value", help="Value to fill")
   p.add_argument("--tab", help="Target tab ID")
   p.set_defaults(func=cmd_fill)

   # select
   p = sub.add_parser("select", help="Select a dropdown option")
   p.add_argument("target", help="@eN ref or CSS selector")
   p.add_argument("value", help="Option value to select")
   p.add_argument("--tab", help="Target tab ID")
   p.set_defaults(func=cmd_select)

   # key
   p = sub.add_parser("key", help="Send a keypress")
   p.add_argument("key_name", metavar="key", help="Key name: Enter, Tab, a, etc.")
   p.add_argument("--meta", action="store_true", help="Hold Cmd/Meta")
   p.add_argument("--ctrl", action="store_true", help="Hold Control")
   p.add_argument("--shift", action="store_true", help="Hold Shift")
   p.add_argument("--alt", action="store_true", help="Hold Alt/Option")
   p.add_argument("--tab", help="Target tab ID")
   p.set_defaults(func=cmd_key)

   # scroll
   p = sub.add_parser("scroll", help="Scroll the page")
   p.add_argument("--down", type=int, metavar="PX", help="Scroll down by pixels")
   p.add_argument("--up", type=int, metavar="PX", help="Scroll up by pixels")
   p.add_argument("--to", metavar="REF", help="Scroll element into view (@eN or CSS)")
   p.add_argument("--tab", help="Target tab ID")
   p.set_defaults(func=cmd_scroll)
   ```

   **Add command handlers:**

   ```python
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
   ```

   **Verification:**
   ```bash
   aslan nav https://example.com --wait idle
   aslan tree
   aslan click @e0         # click the first link
   aslan nav https://example.com --wait idle
   aslan fill "@e0" "test"  # will error if @e0 isn't an input — that's fine, verify error msg
   aslan key Enter
   aslan scroll --down 300
   aslan scroll --up 100
   ```

   ---

   #### Work Item: `cmd-screenshot`

   **Goal:** Add `shot` command.

   **Add to `_build_parser()` in `cli.py`:**

   ```python
   # shot
   p = sub.add_parser("shot", help="Take a screenshot")
   p.add_argument("path", nargs="?", default="/tmp/aslan-screenshot.jpg",
                   help="Output file path (default: /tmp/aslan-screenshot.jpg)")
   p.add_argument("--quality", type=int, default=70, help="JPEG quality 0-100 (default: 70)")
   p.add_argument("--width", type=int, default=1440, help="Viewport width (default: 1440)")
   p.add_argument("--tab", help="Target tab ID")
   p.set_defaults(func=cmd_shot)
   ```

   **Add command handler:**

   ```python
   def cmd_shot(args: argparse.Namespace) -> None:
       tab = _current_tab(args)
       b = _connect()
       try:
           size = b.save_screenshot(args.path, tab_id=tab, quality=args.quality, width=args.width)
           print(f"{args.path} ({size} bytes)")
       finally:
           b.close()
   ```

   **Verification:**
   ```bash
   aslan nav https://example.com
   aslan shot
   # /tmp/aslan-screenshot.jpg (45231 bytes)
   aslan shot /tmp/test.jpg --quality 90 --width 1920
   ls -la /tmp/test.jpg
   ```

   ---

   #### Work Item: `cmd-tabs`

   **Goal:** Add `tabs`, `tab:new`, `tab:close`, `tab:use`, `tab:wait` commands.

   **Add to `_build_parser()` in `cli.py`:**

   ```python
   # tabs
   p = sub.add_parser("tabs", help="List all open tabs")
   p.add_argument("--json", action="store_true", dest="json_output")
   p.set_defaults(func=cmd_tabs)

   # tab:new
   p = sub.add_parser("tab:new", help="Create a new tab and switch to it")
   p.add_argument("url", nargs="?", help="URL to navigate to")
   p.add_argument("--hidden", action="store_true", help="Create hidden tab")
   p.add_argument("--width", type=int, default=1440)
   p.add_argument("--height", type=int, default=900)
   p.add_argument("--json", action="store_true", dest="json_output")
   p.set_defaults(func=cmd_tab_new)

   # tab:close
   p = sub.add_parser("tab:close", help="Close a tab")
   p.add_argument("tab_id", nargs="?", help="Tab ID to close (default: current tab)")
   p.set_defaults(func=cmd_tab_close)

   # tab:use
   p = sub.add_parser("tab:use", help="Switch the current tab")
   p.add_argument("tab_id", help="Tab ID to switch to")
   p.set_defaults(func=cmd_tab_use)

   # tab:wait
   p = sub.add_parser("tab:wait", help="Wait for a CSS selector to appear")
   p.add_argument("selector", help="CSS selector to wait for")
   p.add_argument("--timeout", type=int, default=5000, help="Timeout in ms (default: 5000)")
   p.add_argument("--tab", help="Target tab ID")
   p.set_defaults(func=cmd_tab_wait)
   ```

   **Add command handlers:**

   ```python
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
   ```

   **Verification:**
   ```bash
   aslan tabs
   # tab0* https://example.com  "Example Domain"
   aslan tab:new https://google.com
   # tab1
   aslan tabs
   # tab0  https://example.com  "Example Domain"
   # tab1* https://google.com   "Google"
   aslan tab:use tab0
   # Switched to tab0
   aslan tab:close tab1
   # Closed tab1. 
   aslan tab:wait "h1" --timeout 3000
   # found
   ```

   ---

   #### Work Item: `cmd-cookies`

   **Goal:** Add `cookies` and `set-cookie` commands.

   **Add to `_build_parser()` in `cli.py`:**

   ```python
   # cookies
   p = sub.add_parser("cookies", help="Get cookies")
   p.add_argument("--url", help="Filter by URL")
   p.add_argument("--tab", help="Target tab ID")
   p.add_argument("--json", action="store_true", dest="json_output")
   p.set_defaults(func=cmd_cookies)

   # set-cookie
   p = sub.add_parser("set-cookie", help="Set a cookie")
   p.add_argument("name", help="Cookie name")
   p.add_argument("value", help="Cookie value")
   p.add_argument("domain", help="Cookie domain (e.g. .example.com)")
   p.add_argument("--path", default="/", help="Cookie path (default: /)")
   p.add_argument("--expires", type=float, help="Expiry as Unix timestamp")
   p.add_argument("--tab", help="Target tab ID")
   p.set_defaults(func=cmd_set_cookie)
   ```

   **Add command handlers:**

   ```python
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
   ```

   **Verification:**
   ```bash
   aslan nav https://example.com
   aslan cookies
   aslan set-cookie test val123 .example.com
   # ok
   aslan cookies --json
   ```

   ---

   #### Work Item: `cli-reference-doc`

   **Goal:** Create `sdk/python/CLI_REFERENCE.md` — the agent-facing cheat sheet for all CLI commands. This is what the rewritten skill will load instead of `SDK_REFERENCE.md`.

   **Create `sdk/python/CLI_REFERENCE.md`:**

   Write a concise reference doc (~150 lines) covering every command with:
   - Command syntax
   - What it prints
   - Gotchas

   Structure it as:

   ```markdown
   # Aslan Browser CLI — Agent Reference

   Quick reference for AI agents. Run `aslan <command>`.

   ## Connection
   - The CLI connects to `/tmp/aslan-browser.sock` automatically.
   - A state file at `/tmp/aslan-cli.json` tracks the current tab.
   - All commands target the current tab unless `--tab <id>` is given.

   ## Commands
   [one section per command group: Navigation, Reading, Interaction, Screenshots, Tabs, Cookies]
   [show exact command + example output for each]

   ## Gotchas
   [compact list of the most important things]
   ```

   Model it after `SDK_REFERENCE.md` but for CLI. Much shorter — no code blocks with `import`, no `with` blocks, no `b.method()` calls. Just `aslan` commands.

   CRITICAL: This doc must be self-contained. An agent reading only this file should know how to drive the browser.

   **Verification:**
   - Read the file in full.
   - Spot-check 3 command examples by actually running them.

   ---

   #### Work Item: `rewrite-skill`

   **Goal:** Rewrite `skills/aslan-browser/SKILL.md` to teach CLI usage instead of Python SDK. Rewrite `skills/aslan-browser/SDK_REFERENCE.md` to be the CLI reference. Update `skills/aslan-browser/knowledge/core.md` for CLI-specific operational rules.

   **This is the highest-value work item.** The whole point of the CLI is to shrink the skill's token footprint and eliminate the agent's need to write Python.

   **Rewrite `skills/aslan-browser/SKILL.md`:**

   The new skill should be dramatically shorter. Key changes:

   1. **Remove all Python SDK instruction.** No `from aslan_browser import`, no `with AslanBrowser() as b:`, no heredoc patterns.
   2. **Replace with CLI commands.** Every example becomes a bash one-liner.
   3. **Simplify the driving protocol.** The loop becomes:
      ```
      aslan nav <url> --wait idle     # navigate
      aslan tree                       # read the page
      # (agent decides next action)
      aslan click @e3                  # act
      aslan tree                       # read again
      ```
   4. **Keep the knowledge loading section.** That's still valuable.
   5. **Keep the knowledge compilation section.** That's still valuable.
   6. **Kill the SDK Reference loading.** Replace with CLI Reference.
   7. **Simplify the "verify Aslan is running" step** to just `aslan status`.

   Target: ~150 lines (down from ~300+). The skill context drops from ~5,000 tokens to ~1,500.

   **Replace `skills/aslan-browser/SDK_REFERENCE.md`:**

   Copy (or symlink) `sdk/python/CLI_REFERENCE.md` into the skill directory. The agent loads this instead of the Python SDK reference.

   **Update `skills/aslan-browser/knowledge/core.md`:**

   Replace Python-specific gotchas with CLI-specific ones:
   - Remove: "evaluate MUST have explicit return" (the CLI command docs cover this)
   - Remove: "contenteditable fields — use evaluate with execCommand" (still true but expressed as `aslan eval "..."`)
   - Remove: all `AslanBrowser()` usage patterns
   - Add: `aslan eval` requires "return" prefix
   - Add: quote shell arguments containing spaces: `aslan fill @e0 "hello world"`
   - Add: use `aslan eval 'return ...'` with single quotes to avoid shell escaping issues with double quotes in JS
   - Keep: ATS blocks http://, always use https://
   - Keep: contenteditable workaround (but expressed as `aslan eval` command)

   **Verification:**
   - Read the rewritten SKILL.md in full. It should make sense as a standalone instruction set.
   - Count approximate tokens — target <1,500 for the skill itself.
   - Simulate an agent session: load the skill, run `aslan status`, navigate to a page, read the tree, click something, take a screenshot. Verify the instructions are sufficient.

   ---

   #### Work Item: `integration-tests`

   **Goal:** Create `sdk/python/tests/test_cli.py` — automated tests for the CLI.

   **Create `sdk/python/tests/test_cli.py`:**

   Test strategy: use `subprocess.run(["aslan", ...])` to test the CLI end-to-end. The app must be running.

   ```python
   """Integration tests for the aslan CLI. Requires aslan-browser to be running."""

   import json
   import os
   import subprocess
   import pytest

   def run_aslan(*args: str, check: bool = True) -> subprocess.CompletedProcess:
       """Run an aslan CLI command and return the result."""
       return subprocess.run(
           ["aslan", *args],
           capture_output=True,
           text=True,
           check=check,
       )

   def test_status():
       r = run_aslan("status")
       assert "Connected" in r.stdout

   def test_nav_and_title():
       run_aslan("nav", "https://example.com", "--wait", "load")
       r = run_aslan("title")
       assert "Example Domain" in r.stdout

   def test_tree():
       run_aslan("nav", "https://example.com", "--wait", "load")
       r = run_aslan("tree")
       assert "@e" in r.stdout
       assert "link" in r.stdout or "heading" in r.stdout

   def test_tree_json():
       run_aslan("nav", "https://example.com", "--wait", "load")
       r = run_aslan("tree", "--json")
       data = json.loads(r.stdout)
       assert isinstance(data, list)
       assert len(data) > 0
       assert "ref" in data[0]

   def test_url():
       run_aslan("nav", "https://example.com", "--wait", "load")
       r = run_aslan("url")
       assert "example.com" in r.stdout

   def test_text():
       run_aslan("nav", "https://example.com", "--wait", "load")
       r = run_aslan("text", "--chars", "200")
       assert "Example Domain" in r.stdout

   def test_eval():
       run_aslan("nav", "https://example.com", "--wait", "load")
       r = run_aslan("eval", "return document.title")
       assert "Example Domain" in r.stdout

   def test_screenshot():
       path = "/tmp/aslan-cli-test.jpg"
       if os.path.exists(path):
           os.remove(path)
       run_aslan("nav", "https://example.com", "--wait", "load")
       r = run_aslan("shot", path)
       assert os.path.exists(path)
       assert "bytes" in r.stdout

   def test_click():
       run_aslan("nav", "https://example.com", "--wait", "load")
       r = run_aslan("click", "@e0", check=False)
       # @e0 might not be clickable, just verify the command runs
       assert r.returncode == 0 or "Error" in r.stderr

   def test_tab_lifecycle():
       r = run_aslan("tab:new", "https://example.com")
       tab_id = r.stdout.strip()
       assert tab_id.startswith("tab")

       r = run_aslan("tabs")
       assert tab_id in r.stdout

       run_aslan("tab:close", tab_id)
       r = run_aslan("tabs")
       assert tab_id not in r.stdout

   def test_key():
       run_aslan("nav", "https://example.com", "--wait", "load")
       r = run_aslan("key", "Tab")
       assert r.returncode == 0

   def test_scroll():
       run_aslan("nav", "https://example.com", "--wait", "load")
       r = run_aslan("scroll", "--down", "200")
       assert r.returncode == 0
   ```

   **Verification:**
   ```bash
   cd sdk/python && pip install -e ".[dev]" && python3 -m pytest tests/test_cli.py -v && cd ../..
   ```

   All tests should pass with the app running.

   ---

6. **Verify this item:**
   Follow the verification steps listed in the work item's guidance above.

7. **Update state:**
   ```bash
   jq --arg id "ITEM_ID" '(.workItems[] | select(.id == $id) | .status) = "done"' docs/workflows/state/phase-9-plan.json > tmp.json && mv tmp.json docs/workflows/state/phase-9-plan.json
   ```

8. **Update notes:**
   Add any discoveries, edge cases, or gotchas to `docs/workflows/notes.md`.

9. **Return to step 1.**

### 3. Completion

1. Show final progress:
   ```bash
   jq '[.workItems[].status] | group_by(.) | map({(.[0]): length}) | add' docs/workflows/state/phase-9-plan.json
   ```

2. Verify the complete phase:
   - All work items have status `"done"`.
   - `pip install -e sdk/python` installs the `aslan` CLI on PATH.
   - `aslan --version` prints version.
   - `aslan status` connects successfully.
   - All commands work: `nav`, `tree`, `click`, `fill`, `key`, `scroll`, `shot`, `eval`, `title`, `url`, `text`, `tabs`, `tab:new`, `tab:close`, `tab:use`, `tab:wait`, `cookies`, `set-cookie`, `back`, `forward`, `reload`.
   - `--json` flag works on tree, nav, tabs.
   - `--tab` flag overrides current tab.
   - State file `/tmp/aslan-cli.json` tracks current tab correctly.
   - Integration tests pass.
   - Rewritten skill loads cleanly and teaches CLI usage.
   - CLI_REFERENCE.md is self-contained.

3. Run the full integration test suite:
   ```bash
   cd sdk/python && python3 -m pytest tests/ -v && cd ../..
   ```

4. End-to-end agent simulation: Pretend you are an agent. Load the rewritten skill. Execute a 5-step browsing task using only `aslan` CLI commands. Verify the experience is smooth and token-efficient.

5. Add to `docs/workflows/notes.md`:
   ```
   ## Phase 9 — CLI

   **Status:** Complete ✅

   ### Changes
   - Added `aslan` CLI tool (sdk/python/aslan_browser/cli.py)
   - Entry point via pyproject.toml [project.scripts]
   - State file at /tmp/aslan-cli.json tracks current tab
   - 17 commands covering navigation, reading, interaction, screenshots, tabs, cookies
   - CLI_REFERENCE.md — agent-facing cheat sheet
   - Rewrote SKILL.md to teach CLI instead of Python SDK
   - Updated knowledge/core.md for CLI-specific gotchas
   - Integration tests in tests/test_cli.py

   ### Token Impact
   - Per-interaction: ~200 tokens → ~30 tokens (85% reduction)
   - Skill context: ~5,000 tokens → ~1,500 tokens (70% reduction)
   ```

6. **Commit all changes:**
   ```bash
   git add -A
   git status
   git commit -m "Phase 9: CLI — token-efficient agent interface

   - Add 'aslan' CLI tool with 17 commands (nav, tree, click, fill, key, etc.)
   - Zero new dependencies — wraps existing Python SDK
   - State file tracks current tab across invocations
   - 85% token reduction per agent interaction vs Python SDK
   - Rewrite skill to teach CLI instead of Python scripts
   - CLI_REFERENCE.md agent cheat sheet
   - Integration tests"
   ```

7. Update `docs/workflows/README.md` to include Phase 9 in the phase table.
