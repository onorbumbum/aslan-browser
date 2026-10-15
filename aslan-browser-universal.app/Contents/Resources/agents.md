# Agents Guide

Instructions for AI agents working on the Aslan Browser codebase. Read this at the start of every session.

---

## Semantic Versioning

Aslan Browser follows [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`

| Bump | When | Example |
|---|---|---|
| **PATCH** (`1.0.1` → `1.0.2`) | Bug fixes, small tweaks, removing/changing defaults | Removed custom user agent |
| **MINOR** (`1.0.2` → `1.1.0`) | New features, new JSON-RPC methods, new SDK methods | Added batch API, session management |
| **MAJOR** (`1.1.0` → `2.0.0`) | Breaking changes to protocol, SDK, or behavior | Changed socket path, renamed methods |

### How to Bump

Version is stored in `aslan-browser.xcodeproj/project.pbxproj` in two fields across all build configurations:

- **`MARKETING_VERSION`** — the user-facing version string (e.g., `1.0.1`)
- **`CURRENT_PROJECT_VERSION`** — the build number (integer, increment with every release)

Update all occurrences (there are 6 of each — Debug/Release × app/tests/UITests):

```bash
cd aslan-browser
# Bump version (replace OLD and NEW as needed)
sed -i '' 's/MARKETING_VERSION = OLD;/MARKETING_VERSION = NEW;/g' aslan-browser.xcodeproj/project.pbxproj
sed -i '' 's/CURRENT_PROJECT_VERSION = OLD;/CURRENT_PROJECT_VERSION = NEW;/g' aslan-browser.xcodeproj/project.pbxproj
```

**Verify:**
```bash
grep "MARKETING_VERSION\|CURRENT_PROJECT_VERSION" aslan-browser.xcodeproj/project.pbxproj
```

All 6 lines of each should show the new value.

### About Panel

The app has a custom About panel (menu → "About Aslan Browser") that reads version from `Bundle.main`. It automatically picks up the `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` values from the built binary — no code changes needed when bumping.

### When to Bump

**CRITICAL: Every commit that changes app behavior MUST include a version bump.** This includes:

- Any change to Swift source files in `aslan-browser/`
- Any change to `ScriptBridge.swift` (injected JS)
- Any change to the JSON-RPC protocol
- Any change to build settings that affect the binary

**Does NOT require a version bump:**
- Documentation-only changes (`docs/`, `README.md`)
- Python SDK changes (SDK has its own version in `pyproject.toml`)
- Test changes
- Workflow/plan file changes

---

## Build & Release Workflow

Every time you make changes to the Swift source:

### 1. Bump the version

Determine the appropriate bump level (patch/minor/major) based on the changes.

### 2. Build universal binary

Build a single universal binary (arm64 + x86_64) for all Macs:

```bash
cd /Users/onorbumbum/_PROJECTS/aslan-browser/aslan-browser
xcodebuild -project aslan-browser.xcodeproj -scheme aslan-browser \
  -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Confirm `** BUILD SUCCEEDED **` before proceeding.

Verify it's universal:
```bash
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/aslan-browser-*/Build/Products/Release"
lipo -info $DERIVED/aslan-browser.app/Contents/MacOS/aslan-browser
# Should show: x86_64 arm64
```

### 3. Install to /Applications

```bash
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/aslan-browser-*/Build/Products/Release"
rm -rf /Applications/aslan-browser.app
cp -R $DERIVED/aslan-browser.app /Applications/
```

### 4. Commit and push

```bash
git add -A
git commit -m "Brief description of changes"
git push
```

### 5. Create GitHub release with binary

Package the universal binary and create a GitHub release:

```bash
# Package
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/aslan-browser-*/Build/Products/Release"
cd $DERIVED
ditto -c -k --sequesterRsrc --keepParent aslan-browser.app /tmp/aslan-browser-X.Y.Z-universal.zip

# Create release (replace X.Y.Z and write appropriate notes)
cd /Users/onorbumbum/_PROJECTS/aslan-browser/aslan-browser
gh release create vX.Y.Z \
  /tmp/aslan-browser-X.Y.Z-universal.zip \
  --title "vX.Y.Z — Short Title" \
  --notes "Release notes in markdown"
```

**Release notes should include:** what's new, download table, quick install snippet, requirements.
See previous releases for format: `gh release view v1.1.0`

**One binary only:** Ship `aslan-browser-X.Y.Z-universal.zip` (arm64 + x86_64). No separate arch-specific builds.

---

## Other Conventions

- Always read `docs/workflows/conventions.md` for coding standards.
- Always read `docs/workflows/notes.md` for known gotchas.
- After discovering new gotchas, append them to `notes.md`.
- After every session, commit all changes — never leave uncommitted work.
