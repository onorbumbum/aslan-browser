# Create a public Facebook Page event

## Inputs
- Confirmed event date, local start/end time, venue/address, description, cover graphic.
- Page identity. For We Care Medicare the Page events URL is `https://www.facebook.com/wecaremedicare/events/`.

## Steps
1. Read the Page Events tab to check for duplicates. It lists Upcoming separately from Past.
2. Open `https://www.facebook.com/events/create/` directly. The create dialog opened from the Page tab can remain on a loading skeleton.
3. Verify the host button names the intended Page.
4. Enter React fields with focus plus `document.execCommand('insertText',false,text)`. For existing input values call `select()` first, then `blur()` for date/time normalization. `aslan type` can change the DOM without committing React state. Verify after another action.
5. Search `input[aria-label="Time zone"]` for `Pacific`, wait for the results, then choose the option `America/Los_Angeles`. The timezone defaults to the browser's local zone, not the venue's. The search option and input can keep showing the current-day abbreviation PDT even for a November event. The Olson timezone still applies PST correctly; verify the published event's actual timestamp by converting the displayed viewer-local time rather than trusting the abbreviation.
6. Enter start date/time. Click the `End date and time` add button and enter the real end date/time.
7. Search `input[aria-label="Add location"]`. Only choose a listed venue if its address matches. Otherwise enter the full venue/address and choose `Just use "..."`. Do not choose a similarly named place in another state.
8. Enter the description into textarea using focus plus execCommand. Read back `.value` before publishing.
9. Upload one cover with `aslan upload`. Subsequent uploads ADD images to a carousel instead of replacing the original. Edit cover menu → Remove All clears the draft images; then upload only the desired cover.
10. Verify dates, local timezone, address, description and loaded image dimensions. The create dialog's image region crops roughly 2.7:1; a 4:3 poster loses bottom text. Pad the approved graphic on a matching-color 1920x710 canvas to retain all text instead of publishing a clipped cover.
11. Click Create event once. Creation may succeed while the form remains on a spinner. Check the Page Events listing in a new tab before retrying, to avoid duplicates.
12. Open the new event permalink. Verify Page host, public status, venue, duration and displayed start/end. Facebook displays viewer-local time; convert it back to the intended venue time. A Page co-host acceptance notification can appear during successful creation.

## Scope
Do not boost, invite followers, share into groups, or pin the event without authorization. Keep a durable per-event ledger of verified permalinks.
