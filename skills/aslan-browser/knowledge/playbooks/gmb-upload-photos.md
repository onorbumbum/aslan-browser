# Upload approved GBP photos

## Inputs

- Exact managed business location ID and photo files.
- Explicit approval of selected images, cover choice, and any deletions.

## Prerequisites

- Authenticated Google account with business access.
- Native Safari-compatible user-agent. Bare WKWebView user-agents may receive simplified Search without owner controls. Verify navigator.userAgent and the rendered owner controls.
- Dedicated tab, with explicit --tab on each action when other work is running.

## Steps

1. Open Business Profile Manager, read the exact business row, and follow its photo link in your own tab. Confirm the location ID and business name.
2. Google Search embeds the owner photo interface in an iframe. Read its src, then navigate directly to that observed URL in the dedicated tab.
3. Open the owner's Photos button to obtain the iframe URL ending in `/promote/photos/mediatool`. Navigate directly to that observed URL. Use Add a cover photo, or Change cover when a cover exists, FIRST for the approved cover. Do not upload it to the general gallery first; cover uploads create a separate media record rather than promoting the existing gallery record.
4. Read the upload page. It has an input[type=file] accepting JPEG/PNG. Use `aslan upload /absolute/file.jpg --tab TAB` after confirming Posting publicly as the correct business. Uploading submits immediately; there may be no extra Publish button.
5. Read the result. Directly opened upload pages can become blank below the dialog header after success. Do not retry blindly. Reconcile via the GBP media list API, verifying the new resource, category, and thumbnail.
6. Navigate back to the observed general add-photos URL for the next approved image. Read the page, upload one image, then verify before proceeding.
7. Verify all original media resources remain, the cover is tagged COVER, and new thumbnails match approved files. Browser uploads may omit description fields.

## Limits

- Blank post-upload UI does not imply failure. Conversely it does not prove success: the LOGO uploader has gone blank after file selection without creating a media record. Reconcile both the API category and the manager's Add a logo state before claiming completion or retrying.
- Google may display a different cover publicly despite the saved COVER category. The manager's `[role=gridcell][aria-label="Cover"]` exposes the selected media ID as `data-pid` and moderation text such as PENDING. Verify that cell after reloading; a saved COVER resource alone does not prove public approval.
- Directly opened upload pages may not respond to their Back button. Return to the observed manager URL rather than repeatedly clicking Back.
- If an extra copy was created, obtain deletion approval for that exact new resource. Never delete an original photo to correct upload counts.
