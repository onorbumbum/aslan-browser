# Release Config — aslan-browser

## Repository

- remote: origin
- branch: main

## Version Locations

| File | Pattern | Description |
|---|---|---|
| `aslan-browser.xcodeproj/project.pbxproj` | `MARKETING_VERSION = X.Y.Z;` (multiple occurrences) | App version displayed in About panel and GitHub releases |
| `aslan-browser.xcodeproj/project.pbxproj` | `CURRENT_PROJECT_VERSION = N;` (multiple occurrences) | Build number — increment by 1 each release |
| `sdk/python/pyproject.toml` | `version = "X.Y.Z"` | Python SDK version |
| `sdk/python/aslan_browser/__init__.py` | `__version__ = "X.Y.Z"` | Python SDK runtime version (read by CLI --version) |

## Version Sync Rules

- App version follows semver: `MAJOR.MINOR.PATCH`
- Build number (`CURRENT_PROJECT_VERSION`) increments by 1 each release (currently at 7 for v1.5.0)
- Python SDK minor tracks app minor: app `1.5.0` → SDK `0.5.0` (major is always 0 until 1.0 app release)
- Update ALL occurrences of each pattern in project.pbxproj (there are 5 of each)

## Build

```bash
xcodebuild build \
  -scheme aslan-browser \
  -configuration Release \
  -arch arm64 -arch x86_64 \
  ONLY_ACTIVE_ARCH=NO \
  -derivedDataPath .build
```

## Verify Build

```bash
ls -lh .build/Build/Products/Release/aslan-browser.app
```

## Package

```bash
cd .build/Build/Products/Release
zip -r /tmp/aslan-browser-{version}-universal.zip aslan-browser.app
ls -lh /tmp/aslan-browser-{version}-universal.zip
```

## Release

- artifact_pattern: `/tmp/aslan-browser-{version}-universal.zip`
- title_format: `v{version} — {description}`
- gh_flags: (none)

## Previous Release Reference

```
v1.5.0 — Learn Mode (Record & Playbook Generation)

## What's New

- **Learn Mode** — Record user actions in the browser and auto-generate site-specific playbooks.
  - `aslan learn:start <name>` — Start recording
  - `aslan learn:stop --json` — Stop and get action log
  - `aslan learn:status` — Check recording state
- **Recording UI** — Red ● REC indicator and 📝 Add Note button in toolbar
- **Shadow DOM tracing** — `event.composedPath()` captures full element path
- **Post-action screenshots** — Each action triggers screenshot 500ms later

## Download

Download `aslan-browser-1.5.0-universal.zip`, unzip, and move to `/Applications/`.

## Python SDK

SDK version 0.5.0 — install from source: `pip install -e sdk/python`
```
