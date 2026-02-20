# Core Browser Knowledge

Operational rules for driving Aslan via the `aslan` CLI. Loaded every session.

---

## CLI Basics

- Each `aslan` command connects, runs one action, disconnects. No persistent state except `/tmp/aslan-cli.json` (current tab).
- `aslan eval` MUST have explicit `return` — returns nothing without it
- Quote shell arguments with spaces: `aslan fill @e0 "hello world"`
- Use single quotes for JS containing double quotes: `aslan eval 'return document.querySelector("h1").textContent'`
- Refs (`@eN`) are ephemeral — each `aslan tree` reassigns them. Never reuse refs from a previous tree call.

## WKWebView

- ATS blocks `http://` — always use `https://`
- Default UA is Chrome — if a site blocks or degrades, check UA first
- `--wait idle` is slower but safer for SPAs. Use `--wait load` for static pages.

## Launch

- Confirm running: `aslan status` must print "Connected". If it fails → wrong binary or app not running.
- Always launch from DerivedData, not `/Applications/`.

## Interaction Patterns

- **contenteditable fields** (LinkedIn, Facebook, Notion): `aslan fill` sets `.value` which has no effect.
  Use `aslan type` instead — it auto-detects contenteditable and uses `execCommand("insertText")`.
  For multi-line rich text, `aslan eval` with innerHTML is still better (e.g. LinkedIn's Quill editor with `<p>` tags).
- **File uploads**: Native picker can't be automated. Use `aslan upload <file>` — it handles base64 encoding and DataTransfer injection automatically.
  Click the media/upload button first so the `input[type=file]` is in the DOM, then: `aslan upload /path/to/photo.jpg`
  Use `--selector` if there are multiple file inputs.
- **React inputs**: Many React apps ignore `.value` changes.
  Use `aslan type` — it dispatches proper `input` and `change` events after setting `.value`.

## Operational Rules

- Closing all tabs is fine — socket stays alive, create new tabs as needed
- To keep tabs open for user review: use `tab0` (survives cleanup) or don't close
- Multi-line JS in `aslan eval`: use single quotes around the whole script, keep it as compact as possible
- Tab not found: CLI auto-resets to tab0 and retries once
- After clicking a link that navigates: use `aslan wait --idle` before reading the new page
- `aslan wait --load` is faster but less thorough than `--idle` (no network/DOM stability check)
