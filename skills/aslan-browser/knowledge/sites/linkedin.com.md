# LinkedIn — Site Knowledge

## Rich Text Editor (ql-editor)

LinkedIn uses a Quill-based `.ql-editor` div (contenteditable).

- `fill()` does NOT work — sets .value which has no effect on contenteditable
- For simple text: `execCommand("insertText", false, text)` after focusing the editor
- For multi-line / rich text / links: set `innerHTML` with `<p>` tags per line — more reliable
  ```js
  document.querySelector('.ql-editor').innerHTML = htmlContent
  ```
- Empty lines: `<p><br></p>`
- Links become clickable automatically when using innerHTML

## Media Upload

- MUST click "Media" / "Add a photo" button BEFORE injecting file — `input[type=file]` isn't in DOM until then
- Use DataTransfer API to inject (see core.md interaction patterns)
- Convert WebP to JPG before uploading to be safe

## Authentication

- Chrome UA is set by default — LinkedIn works without issues
- Verify logged-in state by checking for feed identity elements or profile module in accessibility tree
