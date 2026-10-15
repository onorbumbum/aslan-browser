# nextdoor-post-video

Post a video with caption to a Nextdoor business page (We Care Medicare
pattern). Prerequisites: Aslan running, logged in as the business, business
page open, caption text and video file paths ready.

## Steps

1. Open the composer: fresh `aslan tree`, click the first `button "Post"`.
2. Fresh tree, click `button "Add a photo or video"`. This opens the NATIVE
   open panel (separate window named `Open`). See knowledge/sites/nextdoor.com.md.
3. WAIT for the panel via System Events — poll
   `exists window "Open"` of process `aslan-browser` (up to ~12 s). Never send
   keystrokes before it exists; they land on the page instead.
4. Keystroke `Cmd+Shift+G`, type absolute video path, Return, wait 3 s, Return.
5. Confirm `window "Open"` is gone (retry Go-to-folder once if not).
6. Confirm "attachment in post" after the panel closes, then poll upload
   readiness. Upload and processing can take over a minute for 65–120 MB files.
   Do not use a fixed settle delay as proof. Wait until the attachment spinner
   (`[data-testid=attachment-list-container-item] animateTransform`) disappears
   and the composer video has `readyState >= 2`, finite duration, and the correct
   filename in `currentSrc`. Inspect via `aslan eval` before publishing.
7. Fresh tree, `aslan fill` the caption into `textbox "Add a caption"`.
8. Verify `textarea[data-testid=composer-text-field]` value length > 100 and
   contains the TPMO disclaimer and license. Do not use the first generic
   textarea: Nextdoor can retain another hidden textarea with stale text.
9. Fresh tree, click the `button "Post"` that appears AFTER the
   `dialog "create post composer"` line (not the page-header one).
10. Capture the new post URL, then verify on the business page feed
    (`nextdoor.com/page/<slug>/`). Navigation defaults to Overview, so select
    the Posts tab and verify the caption snippet plus video duration there.
    The post-detail URL can show the previous post's text, so never verify there.

## Known notes

- One media attachment per composer flow tested; 65–120 MB h264 .mov
  (1080x1920, 50–86 s) all processed fine.
- Escape key (key code 53) to aslan-browser dismisses a stuck panel.
- If a run dies mid-flow: Escape the panel, reload the page, check the caption
  textarea for stray keystrokes, then restart from step 1.
