---
name: aslan-browser
description: Drive the Aslan Browser for web browsing, scraping, research, automation, and multi-tab tasks. Aslan is a native macOS AI browser controlled via JSON-RPC over a Unix socket. Load this skill whenever the user asks to browse, search, open tabs, scrape pages, or interact with websites using Aslan.
---

# Aslan Browser

Aslan is a native macOS WKWebView browser driven via the `aslan` CLI. Each command connects, executes one action, prints the result, and disconnects.

---

## ⚠️ CRITICAL RULES

1. **Drive interactively.** Navigate → read → decide → act → read. Never pre-plan multi-step scripts.
2. **Use the `aslan` CLI.** Never write Python SDK boilerplate or raw socket code.
3. **Load knowledge first.** Run the setup below before any browsing task.

---

## 1. Setup — Every Session

### 1a. Load knowledge

**Always load (parallel reads):**
1. `SDK_REFERENCE.md` — CLI command reference
2. `knowledge/core.md` — operational rules and gotchas
3. `knowledge/user.md` — user preferences (may not exist)

**Then check for site/task-specific knowledge:**
```bash
ls knowledge/sites/
ls knowledge/playbooks/
```
- If target domain has a file in `knowledge/sites/` → read it
- If task matches a playbook in `knowledge/playbooks/` → read and follow it

### 1b. Verify Aslan is running

```bash
aslan status
```

If not running:
```bash
pkill -x "aslan-browser" 2>/dev/null; sleep 0.5
open ~/Library/Developer/Xcode/DerivedData/aslan-browser-*/Build/Products/Debug/aslan-browser.app
sleep 2
aslan status
```

---

## 2. Interactive Driving Protocol

```
STEP 1 — Orient:  aslan tabs / aslan title / aslan url
STEP 2 — Act:     aslan nav / click / fill / key / eval (ONE action)
STEP 3 — Read:    aslan tree / text / title
STEP 4 — Decide:  next action based on what you see → go to STEP 2, or finish
```

**Example session:**
```bash
aslan nav https://example.com --wait idle
aslan tree                    # read what loaded
aslan click @e2               # act on what you see
aslan tree                    # read the result
```

**Multi-tab:**
```bash
aslan tab:new https://site-a.com
aslan tree
aslan tab:new https://site-b.com
aslan tree
aslan tab:use tab0
```

---

## 3. Knowledge Compilation — MANDATORY

Run after every completed browsing task. Compile discoveries while context is fresh.

**Ask:** *"Did I learn anything that would save time next session?"*

If yes, route to the correct file:

| Discovery | Target file |
|---|---|
| Universal browser/CLI quirk | `knowledge/core.md` |
| Site-specific behavior/selector | `knowledge/sites/{domain}.md` |
| Completed task, no playbook exists | `knowledge/playbooks/{site}-{task}.md` (CREATE) |
| Followed playbook, step was wrong | The playbook file (FIX) |
| User preference | `knowledge/user.md` |

**Rules:** Write reference docs, not logs. No timestamps. Be specific with selectors and commands. Replace outdated info, don't append corrections below it.

---

## Explicit Negations

- DO NOT write Python SDK boilerplate. Use `aslan` CLI commands.
- DO NOT pre-plan multi-step scripts. Drive step by step.
- DO NOT forget `return` in `aslan eval` scripts.
- DO NOT use `http://` URLs — ATS blocks them. Always `https://`.
- DO NOT launch `/Applications/aslan-browser.app` — may be stale.
- DO NOT skip knowledge loading or compilation.
