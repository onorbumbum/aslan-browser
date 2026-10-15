# Core Browser Knowledge

Operational rules for driving Aslan via the `aslan` CLI. Loaded every session.

---

## CLI Basics

- Each `aslan` command connects, runs one action, disconnects. No persistent state except CLI current-tab files: `/tmp/aslan-cli.json` by default, or `/tmp/aslan-cli-session-<name>.json` when `ASLAN_SESSION=<name>` / `--session <name>` is used.
- `aslan eval` MUST have explicit `return` — returns nothing without it
- Quote shell arguments with spaces: `aslan fill @e0 "hello world"`
- Use single quotes for JS containing double quotes: `aslan eval 'return document.querySelector("h1").textContent'`
- Refs (`@eN`) are ephemeral — each `aslan tree` reassigns them. Never reuse refs from a previous tree call.

## WKWebView

- ATS blocks `http://` for remote hosts — always use `https://`. **Exception:** `http://localhost:PORT` works (WKWebView allows local networking) — fine for previewing local dev servers (e.g. `yougrow serve` on :3000).
- Default UA is Chrome — if a site blocks or degrades, check UA first
- `--wait idle` is slower but safer for SPAs. Use `--wait load` for static pages.
- `--wait idle` can return exit-code-1 ("Timeout") even when the page actually loaded. After a timeout, verify with `aslan url` — if it matches the target, treat as success and continue. Don't re-navigate blindly.
- `aslan shot --width N` scales the screenshot output width; it does not resize the WKWebView viewport. Do not treat it as mobile viewport emulation. Verify responsive behavior through real viewport support if available, or label checks as DOM/CSS-based rather than true mobile screenshots.
- `aslan nav file:///absolute/path/index.html --wait load` works for local static artifacts. WKWebView executes classic inline scripts and loads relative local assets; verify images with `img.complete && img.naturalWidth > 0`.

## Responsive Checks & CSS Transitions

- **Viewport emulation:** there is no resize command and `aslan shot --width` only scales the
  output image. To see a page at phone width, render it in a sized `<iframe>`
  (`<iframe src="/path" style="width:390px;height:780px">`) and screenshot that. Media queries
  respond to the iframe's own viewport, so this is a real narrow-viewport render.
  `aslan shot` always captures the full native window (e.g. 1440x864), scaled to `--width`; it
  does not crop to the iframe. Capture at the native width instead and crop the left
  `iframe-width x iframe-height` region with ImageMagick (`magick shot.jpg -crop WxH+0+0 out.jpg`).
- **Don't make the emulation iframe taller than a real device to dodge scrolling.** An iframe
  defines its own viewport for `vh` units — a `height:9000px` iframe makes `100vh` resolve to
  9000px inside it, so any element using `min-height:100vh` (a common full-bleed mobile hero
  pattern) renders enormous and appears to "vanish" off-screen. Size the iframe to a real device
  (e.g. 390x844) and scroll *inside* it instead: `iframe.contentWindow.scrollTo(0, y)`. Verify a
  suspiciously blank capture with `iframe.contentWindow.innerHeight` before concluding the page is
  broken.
- **`scroll-behavior:smooth` races `scroll`/`scrollTo` against `shot`.** If the page (or
  `html`/`body`) sets smooth scrolling, `aslan scroll` and `window.scrollTo` return before the
  animation finishes, so an immediate `aslan shot` — or even `window.scrollY` read back in the same
  eval — can report the pre-scroll position or an in-between frame. Fix at the start of the session:
  `aslan eval "document.documentElement.style.scrollBehavior='auto'; return 1"`. If a screenshot
  ever looks like it didn't scroll, or an image that reports `complete:true` renders blank, retake
  the shot once before concluding something is actually broken — both are transient, not bugs.
- **Make the wrapper same-origin.** A `file://` wrapper renders a `http://localhost` iframe fine
  but cannot script it (`SecurityError` on `contentDocument` and on `cssRules`). Drop the wrapper
  into the site's own served directory instead and load it over `http://localhost:PORT` — then
  `iframe.contentDocument` is fully scriptable. Delete it afterwards. For SSGs that clear their
  output directory (`yougrow build` wipes `dist/`), re-create the probe after every build.
- **CSS transitions never advance inside an iframe.** `el.getAnimations()` reports
  `playState: "running"` with `currentTime: 0` indefinitely, and `getComputedStyle` keeps
  returning the from-value. This affects any element whose visible state depends on a transition
  completing (drawers, sheets, modals). Before screenshotting or asserting such state, inject
  `*{transition:none !important;animation:none !important}` into the iframe document. Verify with
  a control element before concluding the page's CSS is broken.
- **Contrast checks:** screenshot, then sample the JPEG with Pillow and compute WCAG ratios
  against the text colour. Faster and more objective than eyeballing text over photography.

## Launch

- Confirm running: `aslan status` must print "Connected". If it fails → wrong binary or app not running.
- Launch from DerivedData when it exists, never from `/Applications/`. If DerivedData is absent, inspect current checkout builds before launching: `.build/Build/Products/Release/aslan-browser.app` can be old and lack the Safari-compatible UA. The newer `/Users/onorbumbum/_PROJECTS/aslan-browser/aslan-browser/.build-user-agent/Build/Products/Debug/aslan-browser.app` supports full Google owner controls. Confirm startup with `aslan status` and inspect `navigator.userAgent`; startup may take longer than two seconds. Never restart a browser with active user work without permission.

## Interaction Patterns

- **contenteditable fields** (LinkedIn, Facebook, Notion): `aslan fill` sets `.value` which has no effect.
  Use `aslan type` instead — it auto-detects contenteditable and uses `execCommand("insertText")`.
  For multi-line rich text, `aslan eval` with innerHTML is still better (e.g. LinkedIn's Quill editor with `<p>` tags).
- **File uploads**: Native picker can't be automated. Use `aslan upload <file>` — it handles base64 encoding and DataTransfer injection automatically.
  Click the media/upload button first so the `input[type=file]` is in the DOM, then: `aslan upload /path/to/photo.jpg`
  Use `--selector` if there are multiple file inputs.
  Some uploaders ignore the injected change event (no network call). Verify a thumbnail or upload progress appears; if not, the site requires trusted events (drag-and-drop zones often do) and upload must be done by hand. In WebKit, assigning JS-built `DataTransfer.files` to `input.files` silently yields an empty FileList — `input.files.length===0` after assignment means this path is dead.
  Large files (e.g. 10MB+ MP3s) can pin WKWebView when sent as one giant base64 eval payload. If an upload hangs with high `aslan-browser` CPU, use a chunked uploader that sends base64 in smaller RPC chunks and only reconstructs the `File` in-page at the end.
- **React inputs**: Many React apps ignore `.value` changes.
  Use `aslan type` — it dispatches proper `input` and `change` events after setting `.value`.

## Shadow DOM / Web Components

- Modern sites (Reddit, many SPAs) use web components with shadowRoot. The accessibility tree often misses elements inside shadow DOM.
- When `aslan tree` doesn't show an expected element, use `aslan eval` with a recursive shadowRoot search:
  ```javascript
  function deepFind(root, depth=0) {
    if (depth > 5) return null;
    // check current level
    const el = root.querySelector(selector);
    if (el) return el;
    // recurse into shadow roots
    for (const child of root.querySelectorAll("*")) {
      if (child.shadowRoot) {
        const found = deepFind(child.shadowRoot, depth+1);
        if (found) return found;
      }
    }
    return null;
  }
  ```
- Some shadow DOM buttons don't respond to simple `.click()`. Dispatch a full pointer event sequence: `pointerdown → mousedown → pointerup → mouseup → click` (all with `{bubbles: true, cancelable: true}`).
- For form fields inside shadow DOM: find the actual `<textarea>` or `<input>` inside the shadowRoot, set `.value`, then dispatch `input` + `change` events with `{bubbles: true}`.

## Operational Rules

- Closing all tabs is fine — socket stays alive, create new tabs as needed
- To keep tabs open for user review: use `tab0` (survives cleanup) or don't close
- Multi-line JS in `aslan eval`: use single quotes around the whole script, keep it as compact as possible
- To avoid multi-agent tab collisions, set one session per agent: `export ASLAN_SESSION=scout` (or prefix commands with `ASLAN_SESSION=scout`). `tab:new` tags tabs to that named session and normal commands use that session's isolated current-tab state.
- Tab not found: CLI auto-resets to tab0 and retries once
- Some deployed browser builds return `Method not found: session.use` even when the CLI documents named sessions. Fall back to `aslan tab:new <url>`, then verify the new tab is current with `aslan tabs` before navigating.
- After clicking a link that navigates: use `aslan wait --idle` before reading the new page
- `aslan wait --load` is faster but less thorough than `--idle` (no network/DOM stability check)

- `aslan tab:new` may not persist a new tab in every build. If `tab:use tabN` "succeeds" but
  the next command targets the old tab, the CLI silently fell back to tab0 — and a following
  `aslan nav` will navigate the **user's** tab away, destroying its state. Always verify with
  `aslan tabs` / `aslan url` before navigating, and never suppress `tab:use` output.
- `aslan nav "http://host/?query"` (bare `/` path plus a query) can silently no-op. Verify
  with `aslan url` after; use an explicit path like `/index.html` if it doesn't take.
- `aslan eval` fails with a bare "JavaScript error" on multi-line scripts. Keep eval scripts
  to a single line. Async works: return a promise and it resolves.
- Multi-step evals against a page the user is also looking at will race with their typing.
  Filter/search state you did not set is probably theirs — test in a fresh tab before
  concluding you have a bug.

## Learn Mode

- `aslan learn:start <name>` begins recording all user actions across all tabs.
- `aslan learn:stop --json` returns the full action log with composedPath data for shadow DOM.
- Screenshots are saved to `/tmp/aslan-learn/<name>/` — review them for visual context.
- The action log includes `composedPath` arrays that trace through shadow DOM boundaries — use these to write the correct JS eval selectors in the playbook.
- Input events are debounced (300ms) — the log captures the final value, not every keystroke.
- Navigation events are logged automatically — the page URL/title at each step is always available.
- Do NOT browse during recording. The user is performing the task.

## Sharing the browser with the user

- If the user is actively browsing (current tab changing between commands), their navigation can land on the tab you were automating. Re-check `aslan tabs` when a command suddenly errors or returns the wrong page, pin every command with `--tab <id>`, and if the user took your tab, take a fresh `tab:new` instead of navigating their tab back.

## Launching when the DerivedData build is missing

- If `~/Library/Developer/Xcode/DerivedData/aslan-browser-*/Build/Products/Debug/aslan-browser.app` does not exist, compare `/Applications/aslan-browser.app/Contents/MacOS/aslan-browser` mtime with the repo's `.build` mtime (`~/_PROJECTS/aslan-browser/aslan-browser/.build`). When they match, the /Applications copy is the current build and is safe to `open`.
