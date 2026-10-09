# Aslan Browser CLI — Agent Reference

Quick reference for AI agents. Run `aslan <command>`.

## Connection

- Connects to `/tmp/aslan-browser.sock` automatically.
- State file `/tmp/aslan-cli.json` tracks the current tab.
- `ASLAN_SESSION=<name>` uses isolated state at `/tmp/aslan-cli-session-<name>.json` and auto-creates/targets that named session.
- All commands target the current tab unless `--tab <id>` is given. Most tab-targeting commands also accept `--session <name-or-id>`.
- Each invocation connects, runs one operation, disconnects. No persistent connection.

## Global Flags

| Flag | Description |
|---|---|
| `--tab <id>` | Override the current tab for this command |
| `--session <name-or-id>` | Target current tab in a session for commands that support it |
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

**HTML — get page source:**
```bash
aslan html [--chars <n>] [--selector <css>]
# Default: body innerHTML, 20000 chars. --selector targets a specific element.
```

```
$ aslan html --selector "h1"
Example Domain
```

**Eval example:**
```
$ aslan eval "return document.querySelectorAll('a').length"
1
```

---

## Interaction

```bash
aslan click <ref-or-selector>              # Click @e3 or "button.submit"
aslan fill <ref-or-selector> <value>       # Fill input field (input/textarea only)
aslan type <ref-or-selector> <value>       # Type text — works on contenteditable too
aslan select <ref-or-selector> <value>     # Select dropdown option
aslan key <key> [--meta] [--ctrl] [--shift] [--alt]   # Keypress
aslan scroll [--down <px>] [--up <px>] [--to <ref>]   # Scroll (default: --down 500)
```

**Key names:** Enter, Tab, Escape, ArrowDown, ArrowUp, ArrowLeft, ArrowRight, Backspace, Delete, a, b, etc.

**Examples:**
```bash
aslan click @e2
aslan fill @e5 "hello world"        # for <input> / <textarea>
aslan type @e5 "hello world"        # for contenteditable (LinkedIn, Facebook, Notion)
aslan key Enter
aslan key a --meta          # Cmd+A (select all)
aslan scroll --down 500
aslan scroll --to @e10      # Scroll element into view
```

All interaction commands print `ok` on success.

---

## Wait

```bash
aslan wait --idle [--timeout <ms>]   # Wait for network idle + DOM stable
aslan wait --load [--timeout <ms>]   # Wait for document.readyState === "complete"
```

Use after `aslan click` on a link that triggers navigation. Default timeout: 10000ms.

**Example:**
```bash
aslan click @e2            # click a link that navigates
aslan wait --idle          # wait for new page to settle
aslan tree                 # now read the new page
```

---

## File Upload

```bash
aslan upload <file> [--selector <css>] [--name <override>]
# Inject a local file into an input[type=file] via DataTransfer API.
# Default selector: input[type="file"]. Auto-detects MIME type.
```

**Example:**
```bash
# Click the media button first to create the file input, then:
aslan upload /tmp/photo.jpg
# uploaded photo.jpg (52431 bytes)

# Custom selector:
aslan upload /tmp/doc.pdf --selector "#file-upload"
```

---

## Screenshots

```bash
aslan shot [<url>] [<path>] [--width <px>] [--height <px> | --full-page] [--quality <0-100>]
# Default path: /tmp/aslan-screenshot.jpg. Extension picks the format: .png, .jpg, .jpeg
```

With a URL, `shot` opens a temporary hidden tab, loads the page, captures and closes the tab.
Without one it captures the current tab (unchanged unless you pass a size flag).

| Flag | Meaning |
|------|---------|
| `--width W` | Viewport width in px (URL mode default: 1280) |
| `--height H` | Viewport height in px (URL mode default: 720). Single frame only |
| `--full-page` | Capture the whole page at `--width`; height comes from the page. Cannot be combined with `--height` |
| `--quality N` | JPEG quality (ignored for PNG) |

Full-page capture scrolls the page in viewport-sized slices and stitches them (viewport height is
1080, or 844 when `--width` < 768, so `vh` sections size like a real visit). It scrolls the whole
page first so lazy images and scroll-reveal sections load, settles finite CSS animations, and shows
fixed/sticky headers only once at the top. Output is clipped at 16384px tall (a warning is printed).
It takes a few seconds on long pages. Scrolling inner containers (apps with `body { overflow: hidden }`)
is not captured.

**Examples:**
```
$ aslan shot https://example.com out.png --width 1280 --full-page
out.png (183204 bytes)
$ aslan shot https://example.com mobile.png --width 390 --height 844
$ aslan shot /tmp/page.jpg --quality 90          # current tab, as before
```

> Changed: `--width` was an output-scale value (default 1440). It is now the viewport width.
> The Python SDK `width=` keeps its scaling meaning; use `viewport_width=` there.

---

## Tab & Session Management

```bash
aslan sessions                                # List sessions
aslan session:use <name>                      # Create/find session; prints export hint
aslan session:use <name> --shell              # Print: export ASLAN_SESSION=<name>
aslan session:destroy <name-or-id>            # Close all tabs in session

ASLAN_SESSION=scout aslan tab:new https://example.com
ASLAN_SESSION=scout aslan tree                # Uses scout's current tab/state
aslan tabs --session scout                    # List tabs in session
aslan tab:new [<url>] [--hidden] [--session scout]
aslan tab:close [<id>] [--session scout]
aslan tab:use <id> [--session scout]
aslan tab:wait <selector> [--timeout <ms>] [--session scout]
```

**Example:**
```
$ aslan tabs
tab0  https://example.com	"Example Domain"
tab1* https://google.com	"Google"

$ export ASLAN_SESSION=scout
$ aslan tab:new https://github.com
tab2

$ aslan tab:use tab2
Switched to tab2
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
3. **`fill` doesn't work on contenteditable.** Use `aslan type` instead — it auto-detects and handles both input fields and contenteditable divs.
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
