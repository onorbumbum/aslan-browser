# Aslan Browser CLI — Agent Reference

Quick reference for AI agents. Run `aslan <command>`.

## Connection

- Connects to `/tmp/aslan-browser.sock` automatically.
- State file `/tmp/aslan-cli.json` tracks the current tab.
- All commands target the current tab unless `--tab <id>` is given.
- Each invocation connects, runs one operation, disconnects. No persistent connection.

## Global Flags

| Flag | Description |
|---|---|
| `--tab <id>` | Override the current tab for this command |
| `--json` | Output raw JSON (on commands that support it) |

---

## Navigation

```bash
aslan nav <url> [--wait none|load|idle] [--timeout <ms>]
# Navigate. Default: --wait load. Prints title + URL.

aslan back                  # Go back. Prints title + URL.
aslan forward               # Go forward. Prints title + URL.
aslan reload                # Reload. Prints title + URL.
```

**Example:**
```
$ aslan nav https://example.com --wait idle
Example Domain
https://example.com/
```

---

## Reading

```bash
aslan tree                  # Accessibility tree — one line per node
aslan tree --json           # Full tree as JSON array
aslan title                 # Page title
aslan url                   # Current URL
aslan text [--chars <n>]    # Page innerText (default: 3000 chars)
aslan eval <script>         # Evaluate JS — MUST include "return"
```

**Tree output format:**
```
@e0 heading "Example Domain"
@e1 paragraph "This domain is for use..."
@e2 link "More information..."
```

Use `@eN` refs from tree output in `click`, `fill`, `scroll --to`.

**Eval example:**
```
$ aslan eval "return document.querySelectorAll('a').length"
1
```

---

## Interaction

```bash
aslan click <ref-or-selector>              # Click @e3 or "button.submit"
aslan fill <ref-or-selector> <value>       # Fill input field
aslan select <ref-or-selector> <value>     # Select dropdown option
aslan key <key> [--meta] [--ctrl] [--shift] [--alt]   # Keypress
aslan scroll [--down <px>] [--up <px>] [--to <ref>]   # Scroll (default: --down 500)
```

**Key names:** Enter, Tab, Escape, ArrowDown, ArrowUp, ArrowLeft, ArrowRight, Backspace, Delete, a, b, etc.

**Examples:**
```bash
aslan click @e2
aslan fill @e5 "hello world"
aslan key Enter
aslan key a --meta          # Cmd+A (select all)
aslan scroll --down 500
aslan scroll --to @e10      # Scroll element into view
```

All interaction commands print `ok` on success.

---

## Screenshots

```bash
aslan shot [<path>] [--quality <0-100>] [--width <px>]
# Default: /tmp/aslan-screenshot.jpg, quality 70, width 1440
```

**Example:**
```
$ aslan shot /tmp/page.jpg --quality 90
/tmp/page.jpg (52431 bytes)
```

---

## Tab Management

```bash
aslan tabs                          # List tabs (* marks current)
aslan tab:new [<url>] [--hidden]    # Create tab, switch to it
aslan tab:close [<id>]              # Close tab (default: current)
aslan tab:use <id>                  # Switch current tab
aslan tab:wait <selector> [--timeout <ms>]  # Wait for CSS selector
```

**Example:**
```
$ aslan tabs
tab0  https://example.com	"Example Domain"
tab1* https://google.com	"Google"

$ aslan tab:new https://github.com
tab2

$ aslan tab:use tab0
Switched to tab0
```

---

## Cookies

```bash
aslan cookies [--url <url>]                                    # Get cookies
aslan set-cookie <name> <value> <domain> [--path <p>] [--expires <ts>]  # Set cookie
```

---

## Status

```bash
aslan status    # Connection info + tab count
aslan source    # Print SDK source path
```

---

## Gotchas

1. **`aslan eval` requires `return`.** `aslan eval "document.title"` → nothing. Use `aslan eval "return document.title"`.
2. **ATS blocks `http://`.** Always use `https://`. No workaround.
3. **`fill` doesn't work on contenteditable.** Use: `aslan eval 'return (function(){ var el = document.querySelector("[contenteditable]"); el.focus(); document.execCommand("insertText", false, "text"); return "done"; })()'`
4. **Quote shell arguments with spaces.** `aslan fill @e0 "hello world"` — quotes around the value.
5. **Use single quotes for JS with double quotes.** `aslan eval 'return document.querySelector("h1").textContent'`
6. **Refs are ephemeral.** Each `aslan tree` reassigns `@eN` refs. Don't reuse refs from a previous tree call.
7. **`--wait idle` is slower but safer for SPAs.** Use `--wait load` for static pages.
8. **Tab not found auto-recovery.** If the current tab was closed, the CLI resets to tab0 and retries.

---

## Typical Agent Session

```bash
# Navigate and read
aslan nav https://example.com --wait idle
aslan tree

# Interact based on tree
aslan click @e2
aslan tree              # re-read after action

# Fill a form
aslan fill @e5 "search query"
aslan key Enter
aslan tree

# Screenshot for visual verification
aslan shot /tmp/result.jpg
```

**Multi-tab:**
```bash
aslan tab:new https://site-a.com
aslan tree                          # read site A
aslan tab:new https://site-b.com
aslan tree                          # read site B
aslan tab:use tab0                  # switch back
```
