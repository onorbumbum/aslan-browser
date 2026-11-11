# nextdoor.com

## Business page posting (nextdoor.com/page/<slug>/)

- If the top-right avatar is the person's identity and the page has no owner Post control, open the avatar menu and select the business name. Confirm the avatar and composer form now name the business before publishing. The switch may land on a blank ads-management dashboard; its sidebar Post button still opens the business composer.
- A YouTube URL in the caption can generate an embedded video preview without a media upload. Verify the published post includes the actual YouTube link and Play video control.
- The expanded caption can be a role=link div without an href, so clicking it may only expand text. To recover a permalink, open that post's Share dialog and read the encoded Nextdoor /p/<id> URL from its Facebook, X or Email share link. Do not click the external share destination. Verify the recovered permalink and original business Posts feed.

- The page header and sidebar both have a "Post" button; clicking opens the
  "create post composer" dialog: a caption textbox ("Share an update with your
  community." / "Add a caption (optional)"), "Add a photo or video",
  "Add a location", and a dialog-level "Post" button. `aslan tree` shows it as
  `dialog "create post composer"` with all controls as normal refs.
- **Media upload uses a NATIVE macOS open panel.** Clicking "Add a photo or
  video" does not create a usable `input[type=file]` path — it opens a native
  NSOpenPanel as a SEPARATE window named `Open` on process `aslan-browser`
  (not a sheet of the main window). While it is open the page's main thread is
  blocked: every `aslan eval/tree/click` hangs until timeout.
- Driving the panel (only after confirming `exists window "Open"` via System
  Events, never blind):
  1. `tell application "aslan-browser" to activate`
  2. keystroke `g` with `{command down, shift down}` (Go to Folder)
  3. type the absolute file path, Return, wait ~3 s, Return (Open)
  4. confirm `window "Open"` is gone before any further `aslan` command
- After selection the dialog shows `status "N attachment(s) in post."` plus a
  processing spinner; large videos (65–120 MB .mov) need ~10–20 s settle before
  posting. Attachment text: `1 attachment in post.`
- Caption is a plain textarea; `aslan fill` works. Composer posts navigate to
  `nextdoor.com/p/<id>/?view=detail`, which may briefly show the PREVIOUS
  post's content — verify publication on the business page feed, not the
  detail page.
- Image attachments have an `Alt text` button. Its input uses `placeholder="Describe what this media is about"`. CLI fill/type can fail to update React state. Use the native `HTMLInputElement.prototype.value` setter and bubbling `input`/`change` events, then Save. Confirm the button changes to `Alt text added, tap to edit` and verify the published image's alt text.
- Hashtags render as links in Nextdoor posts. TPMO disclaimer and CA license
  lines render as plain text fine.
- The composer keeps unsaved state across navigation; if a run dies mid-flow,
  close it via the `close postbox` button (or reload) before retrying, and
  check the caption textarea for stray keystrokes typed while focus was wrong.
