# Playbook: Create LinkedIn Post

## Inputs

- **text**: string (the post body, may be multi-line)
- **images**: list[filepath] (optional)

## Prerequisites

- Navigate to `https://www.linkedin.com/feed`
- Verify logged in: check accessibility tree for feed identity elements or profile module
- If not logged in → ABORT, tell user to log in manually in Aslan

## Steps

### 1. Open composer

- Click "Start a post" button (look in accessibility tree for button/div containing this text)
- Wait for `.ql-editor` to appear in DOM (poll up to 5s)
- If not found → try alternative selectors: `.share-box-feed-entry__trigger`
- If still not found → add 2s delay and retry (composer modal may be loading)

### 2. Insert text

- Build HTML from text lines:
  - Each line → `<p>{line}</p>`
  - Empty lines → `<p><br></p>`
- Set via evaluate:
  ```js
  document.querySelector('.ql-editor').innerHTML = htmlContent
  ```
- Verify: read back `.ql-editor.innerText` to confirm content was set and is non-empty
- Fallback: if innerHTML doesn't render, try `execCommand("insertText")` for simple text

### 3. Attach images (if provided)

- For each image file:
  - If `.webp` → convert first: `sips -s format jpeg {path} --out {path}.jpg`
- Click "Add media" button — **MUST happen BEFORE file injection**
- Wait for `input[type="file"]` to appear: `aslan tab:wait "input[type=file]"`
- Upload: `aslan upload /path/to/image.jpg`

### 4. Post

- Click "Post" button
- Wait for composer modal to close or feed to refresh
- Verify: confirm the modal is gone

## Known Failure Modes

| Symptom | Cause | Fix |
|---|---|---|
| `.ql-editor` not found | Composer modal hasn't loaded | Add 2s sleep after clicking "Start a post" |
| Image upload silently fails | WebP format or wrong MIME type | Convert to JPG first |
| innerHTML doesn't render properly | Quill re-renders on focus | Set innerHTML, then click outside the editor to trigger Quill's internal update |
| Text appears but loses formatting | Used insertText for multi-line | Switch to innerHTML with `<p>` tags |
