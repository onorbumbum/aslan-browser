# Google Drive

- Folder/file list rows expose Google Drive file IDs in DOM `data-id` attributes. Use `aslan eval` to inspect rows:
  ```javascript
  return JSON.stringify(Array.from(document.querySelectorAll('[role=row], [data-id]')).map(el => ({text:(el.innerText||'').slice(0,200), id:el.getAttribute('data-id')})).filter(x => x.id), null, 2)
  ```
- For non-public/shared folders, `gdown --folder` may fail even when the browser session can see the files.
- Direct `curl` to `drive.google.com/uc?export=download&id=...` with visible browser cookies can still redirect to Google sign-in; validate downloads by checking file magic/header so HTML sign-in pages are not mistaken for images/docs.
- The Drive UI “More actions → Download” may not produce a file in `~/Downloads` under WKWebView/Aslan; prefer user-provided local sync or Drive API/rclone when available.
