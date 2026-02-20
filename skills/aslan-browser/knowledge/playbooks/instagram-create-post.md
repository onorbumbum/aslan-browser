# Playbook: Create Instagram Post

## Inputs

- **image**: filepath (required) — must be JPG or PNG (Instagram does not support WebP)
- **caption**: string (optional, max 2,200 characters)

## Prerequisites

- Navigate to `https://www.instagram.com/`
- Verify logged in: check accessibility tree for user avatars or the "New post" button
- If not logged in → ABORT, instruct user to log in manually in Aslan

## Steps

### 1. Open composer

- Click the "New postCreate" button (button with "New post" or "Create" in its label)
- In the dropdown, click "Post" (link or button labeled "Post")
- Wait for the dialog with heading "Create new post" to appear

### 2. Upload image

- Click "Select from computer" button
- Wait for file picker to activate (aslan upload command handles injection)
- Upload with: `aslan upload <path-to-jpg-or-png>`
- If upload fails with "File couldn't be uploaded" and "This file is not supported" → convert to JPG/PNN and retry

### 3. Crop (optional)

- The crop screen appears automatically after upload
- Click "Next" to accept default crop (or adjust manually then proceed)

### 4. Filters (optional)

- Click "Next" to skip filters (or select a filter and then "Next")

### 5. Add caption

- The caption field is a contenteditable div, NOT an input
- **Use `aslan type`**, not `aslan fill`:
  - `aslan type <ref-or-selector> "Your caption text"`
- Verify content was set by reading back the text via `aslan tree` or `aslan text`

### 6. Share

- Click "Share" button
- Wait for "Sharing" dialog, then "Post shared" confirmation
- Verify the sharing dialog is closed before considering the task complete

## Notes

- **Never use emojis** — they render inconsistently and can cause display issues
- **Avoid em-dashes** — use double hyphens `--` or short dashes `-` instead
- For image formats: Instagram accepts JPG, PNG. WebP, AVIF, and other modern formats are rejected.
- Recommended conversion: `convert input.webp output.jpg` or `sips -s format jpeg input.webp --out output.jpg`

## Known Failure Modes

| Symptom | Cause | Fix |
|---|---|---|
| "File couldn't be uploaded / This file is not supported" | Image is WebP, AVIF, or unsupported format | Convert to JPG or PNG first |
| Caption doesn't appear after typing | Used `fill` instead of `type` on contenteditable | Use `aslan type` |
| Post doesn't share, stays on same screen | Clicked wrong button or modal closed unexpectedly | Click "Share" button again; ensure modal is open |
| Long caption truncated | Exceeded 2,200 character limit | Keep caption under limit |
