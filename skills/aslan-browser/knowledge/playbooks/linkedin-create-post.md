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

- **Simple text:** `aslan type ".ql-editor" "Your post text here"`
- **Multi-line / rich text with links:** Build HTML and set via eval:
  - Each line → `<p>{line}</p>`, empty lines → `<p><br></p>`
  - `aslan eval 'var e = document.querySelector(".ql-editor"); e.innerHTML = htmlContent; return e.innerText.substring(0,100)'`
- Verify: read back content to confirm it was set and is non-empty

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
