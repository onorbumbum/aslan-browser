# Village Creative Opus

## Campaign editing

- Copy a suitable recent campaign instead of creating one from scratch. `Summer Festival 26` is one useful base.
- Campaign list can default to Draft/Scheduled/Paused filters. Clear status filters and use Load everything to find completed campaigns and new copies.
- Duplicate controls use `#item-duplicate-<campaign-id>`, with a Continue confirmation. The copy is Draft, has no scheduled date, and retains audience criteria.
- Copying a campaign also copies its email template. Verify source and copy template IDs before editing.
- Campaign detail fields are inline editors. Click `#campaign-name`, set the resulting input, and click `#submit-tags`. Email subject is also click-to-edit.
- Aslan fill/type can change visible input values without updating React state. Use the native `HTMLInputElement.prototype.value` setter and a bubbling input event. Verify after reload.
- Email Template tab is `#campaign-editor-email-template-tab`; Details is `#campaign-editor-details-tab`.
- Email editor is a cross-origin Unlayer iframe. `window.unlayer` is not the active editor instance. The React fiber for the iframe parent, two returns upward, has the active editor as its first hook value. Its public `saveDesign`, `loadDesign`, and `exportHtml` methods work. Store callback results on window and read them in a later eval.
- Save template after edits and reload to verify. Preserve the brand logo and copyright/unsubscribe merge tags; remove old event links, buttons and artwork.
- Return bounded primitive summaries when inspecting React fibers. Never return a component type object, which can crash the browser during serialization.
- When the client supplies wording and a flyer, preserve that copy and embed the flyer. Only fill requested details and the requested additional note.
- Flyer PDFs can be rendered to PNG with pdftoppm. Upload the image into the existing Unlayer project rather than linking Gmail or embedding base64.
- Unlayer's normal upload sequence, as defined in editor.js, is POST `/v2/editor/auth` with the editor projectId, then POST `/v2/editor/session` with projectId and the real Opus hostname. The bootstrap token from auth cannot authorize uploads; use the session token. Keep tokens in browser memory and never print them.
- Request `/v2/images/upload-url` with filename, width, height and source `upload`. Upload the PNG using its returned presignedPost FormData, including Content-Type, every supplied field and file. A CORS error may occur after S3 has accepted it. GET the returned location and verify the image before any retry.
- Register an accepted upload via POST `/v2/images/save` with the returned key and location, actual filename, dimensions, byte size, contentType and session userId. Use its returned image id/location in the Unlayer design.
- For Unlayer JSON requests, the editor uses Content-Type `text/plain`, Bearer authorization header and an `authorization` body field. Follow the current editor.js rather than assuming endpoints remain unchanged.
- Verify uploaded image rendering and exact client copy in exported HTML after saving and reloading.
- Send Test Email opens a staff recipient selector. Search with the native input setter, verify the option's exact email, then press Enter to select the focused option. Clicking the option can clear search without selecting it. Multiple staff can be selected. Verify the complete selected set before clicking `#submit-send-campaign-test-email` once. Success toast is `Campaign test email sent successfully`.
- Do not schedule or send a campaign without explicit approval. Confirm exact recipients before sending test emails.
