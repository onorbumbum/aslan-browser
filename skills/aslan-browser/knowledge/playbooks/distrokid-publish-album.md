# Playbook: Publish Album on DistroKid

## Inputs

- **album_title**: string
- **song_count**: integer
- **release_date**: `YYYY-MM-DD` — always check actual current date with `date +%Y-%m-%d` before asking the user; never assume
- **artwork_path**: local filepath
- **tracks**: ordered list of objects:
  - `title`: string
  - `file_path`: local filepath (absolute)
  - `instrumental`: boolean
  - `cover_song`: boolean (optional, only when DistroKid asks)
  - `clean`: boolean (optional, only when DistroKid asks)
- **album_id**: string — slug form of the album title (e.g. `konbini-at-2am`); matches `.id` in catalog.json
- **catalog_path**: string — absolute path to catalog.json (lofiall.day default: `/Users/onorbumbum/_SITES/lofiall.day/_scripts/music/catalog.json`)
- **songwriter_first**: string
- **songwriter_last**: string
- **primary_genre_value**: string
- **primary_subgenre_value**: string
- **secondary_genre_value**: string
- **secondary_subgenre_value**: string
- **performer_role**: string
- **performer_name**: string
- **producer_role**: string
- **producer_name**: string

## Prerequisites

- Always verify current date: `date +%Y-%m-%d`
- Always open a **new tab** for the upload: `aslan tab:new https://distrokid.com/new/` — never reuse a stale tab
- Use `--tab <tab_id>` on **every** aslan command after opening the tab — the CLI state resets between invocations and defaults to tab0 (which may not exist)
- Use `https://distrokid.com/mymusic/` if already logged in
- If not logged in, DistroKid sign-in fields are:
  - `#inputSigninEmail`
  - `#inputSigninPassword`
  - `#signinButton`
- Have all MP3s and square cover art ready locally before starting
- If DistroKid prompts for verification or email codes, stop and ask the user to complete that step

## Phase-Based Approach

**Do NOT work per-track.** Work phase by phase across all tracks. This is faster, less error-prone, and easier to verify.

---

## Phase 1 — Navigate to upload form

```bash
aslan nav https://distrokid.com/mymusic/ --wait idle
aslan click '.button-blue[href="/new/"]'
aslan wait --idle
```

Take a screenshot to confirm you're on the upload form (not a login page).

Fallback if logged out:
```bash
aslan nav https://distrokid.com/ --wait idle
aslan click '#signInButtonFrontPage'
```

---

## Phase 2 — Album-level fields

```bash
aslan select '#howManySongsOnThisAlbum' '<song_count>'
```

**Release date — CRITICAL:**
- `aslan fill` alone does NOT trigger DistroKid's validation. Always use eval:
```bash
aslan eval "const f = document.querySelector('#release-date-dp'); f.value = '<YYYY-MM-DD>'; f.dispatchEvent(new Event('change', {bubbles: true})); return f.value"
```
- Verify the returned value matches what you set.

```bash
aslan select '#genrePrimary' '<primary_genre_value>'
aslan select '#subGenrePrimary' '<primary_subgenre_value>'
aslan select '#genreSecondary' '<secondary_genre_value>'
aslan select '#subGenreSecondary' '<secondary_subgenre_value>'
aslan fill '#albumTitleInput' '<album_title>'
```

lofiall.day defaults:
```bash
aslan select '#genrePrimary' '9'
aslan select '#subGenrePrimary' '36'
aslan select '#genreSecondary' '9'
aslan select '#subGenreSecondary' '40'
```

Facebook/Instagram profile questions auto-select "No profile yet" for lofiall.day — no action needed.

---

## Phase 2b — First-release artist profile options

If this is the artist's first release, make sure Spotify/Apple/YouTube/Instagram/Facebook are set to create/use a new artist profile, not another artist already on the DistroKid account:

```bash
aslan eval "
const groups = [
  ['#js-spotify-artist-id-zero-matches-new', '#spotifyNoArtistIDFirst'],
  ['#js-apple-artist-id-zero-matches-new', '#appleNoArtistIDFirst'],
  ['#js-google-artist-id-zero-matches-new', '#googleNoArtistIDFirst'],
  ['#js-instagramProfile-artist-id-zero-matches-new'],
  ['#js-facebookProfile-artist-id-zero-matches-new']
];
function visible(el) { return !!el && !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length); }
for (const selectors of groups) {
  const candidates = selectors.map(s => document.querySelector(s)).filter(Boolean);
  const el = candidates.find(visible) || candidates[0];
  if (el && !el.checked) el.click();
}
return 'artist profile options set';
"
```

Do not click hidden fallback radios if a visible zero-match radio exists — same-name radio groups can uncheck the visible choice.

## Phase 3 — Upload cover art

```bash
aslan upload '<artwork_path>' --selector '#artwork'
```

Take a screenshot to confirm the cover thumbnail appears.

---

## Phase 4 — Set all track titles at once (JS eval)

Build a JS array from your track list and set all titles in one eval — do NOT loop with 20 separate `aslan fill` calls:

```bash
aslan eval "
const titles = [
  'Track 1 Title',
  'Track 2 Title',
  // ... all N titles in order
];
for (let i = 0; i < titles.length; i++) {
  const n = i + 1;
  const input = document.querySelector('input[placeholder=\"Track ' + n + ' title\"]');
  if (input) {
    input.value = titles[i];
    input.dispatchEvent(new Event('input', {bubbles: true}));
    input.dispatchEvent(new Event('change', {bubbles: true}));
  }
}
return 'set ' + titles.length + ' titles';
"
```

---

## Phase 5 — Mark all tracks as instrumental at once (JS eval)

If all tracks are instrumental (lofiall.day default), click all at once:

```bash
aslan eval "
let count = 0;
for (let i = 1; i <= <song_count>; i++) {
  const r = document.querySelector('#js-instrumental-radio-button-' + i);
  if (r && !r.checked) { r.click(); count++; }
}
return 'clicked ' + count + ' instrumental radios';
"
```

If only some tracks are instrumental, pass a boolean array and conditionally click.

---

## Phase 5b — AI disclosure, if applicable

If the release contains AI-generated music/audio, DistroKid requires per-track AI detail selections. You must open and save the per-track modal; setting hidden checkboxes directly does not persist.

For each track:
1. Click Yes: `input[name^="ai_gate_"][track="N"][value="1"]`
2. Open modal: `[data-js-ai-credits-open-modal][data-track="N"]`
3. In `.swal2-popup`, select applicable boxes:
   - Music composed by AI: `input.distroAiMusic`
   - Lyrics written by AI: `input.distroAiLyrics`
   - All audio performed by AI: `input.distroAiRecordingScope[value="full"]`
   - Partial audio performed by AI: `input.distroAiRecordingScope[value="partial"]`
   - If the modal shows an artist-persona choice, select Human artist/group: `input.distroAiArtistPersona[value="0"]` or AI persona: `input.distroAiArtistPersona[value="1"]`. Some releases only show composition, lyrics, and audio-scope controls.
4. If the modal offers "Apply these selections to all songs on this release" and every track has the same AI details, check it before saving. This sets the AI gate and saved tags across the album in one operation.
5. Click `.swal2-confirm` / `.ai-modal-btn-save`.
6. Verify the Yes radio and saved tags for every track. Do not assume the apply-all action persisted without checking all `#ai-saved-tags-N` elements.

## Phase 6 — Upload all audio files one at a time

**DO NOT use parallel tmux sessions for uploads.** The Aslan socket serializes concurrent connections, causing all sessions to block waiting. The browser also needs time between uploads to process each file.

**Upload each track individually and sequentially:**
```bash
aslan upload '/path/to/track1.mp3' --selector '#js-track-upload-1' --tab <tab_id>
aslan upload '/path/to/track2.mp3' --selector '#js-track-upload-2' --tab <tab_id>
# ... etc
```

**Always specify `--tab <tab_id>` on every command** — the CLI state file resets between invocations and defaults to tab0 which may not exist.

**If an upload times out (120s default):** retry immediately — it usually succeeds on the next attempt. Use a 300s timeout for stubborn tracks. The browser may be busy uploading a previous track to DistroKid's servers.

**After a run of successful uploads, DistroKid's JS starts uploading to its servers** in the background, which can block subsequent `aslan upload` calls. If repeated retries time out, wait 30–60 seconds for the browser to settle, then retry.

Do not replace `aslan upload` with a custom `DataTransfer` / localhost `fetch` injection. It can make the file appear attached in the input without properly waking DistroKid's upload/validation pipeline. Use `aslan upload` on the visible `#js-track-upload-N` inputs.

**Verify all uploads via eval — do this before moving on:**
```bash
aslan eval "
const missing = [];
for (let i = 1; i <= <song_count>; i++) {
  const f = document.querySelector('#js-track-upload-' + i);
  if (!f || !f.files || f.files.length === 0) missing.push(i);
}
return missing.length === 0 ? 'ALL FILES PRESENT' : 'MISSING TRACKS: ' + missing.join(', ');
"
```

If any tracks are missing, re-upload only those before continuing.

---

## Phase 7 — Songwriter on track 1, copy to all

```bash
aslan fill 'input[name="songwriter_real_name_first1"]' '<songwriter_first>'
aslan fill 'input[name="songwriter_real_name_last1"]' '<songwriter_last>'
aslan click '#js-copy-songwriters-link-1'
aslan click '.swal2-confirm'
# Dismiss the "Done!" confirmation
aslan click '.swal2-confirm'
```

lofiall.day default: `Aslan Uzunismail`

---

## Phase 8 — Apple Music credits on track 1, copy to all

Open the credits section:
```bash
aslan click '.requirements-item-title'
```

Set performer:
```bash
aslan select '#track-1-performer-1-role' '<performer_role>'
aslan fill '#track-1-performer-1-name' '<performer_name>'
aslan click '#copy-performer'
aslan click '.swal2-confirm'
aslan click '.swal2-confirm'
```

Set producer:
```bash
aslan select '#track-1-producer-1-role' '<producer_role>'
aslan fill '#track-1-producer-1-name' '<producer_name>'
aslan click '#copy-producer'
aslan click '.swal2-confirm'
aslan click '.swal2-confirm'
```

lofiall.day defaults:
- performer role: `Other instrument`, performer name: `Aslan Uzunismail`
- producer role: `Producer`, producer name: `Aslan Uzunismail`

Confirm the Apple Music section badge reads **Complete** before moving on.

---

## Phase 9 — QC CHECK (MANDATORY — do NOT skip or submit before this)

Run this full QC eval and review every line before touching the Done button:

```bash
aslan eval "
const expected = [
  { title: 'Track 1 Title', file: 'expected-filename-fragment-1' },
  { title: 'Track 2 Title', file: 'expected-filename-fragment-2' },
  // ... all tracks
];
const results = [];
let pass = true;
for (let i = 0; i < expected.length; i++) {
  const n = i + 1;
  const titleInput = document.querySelector('input[placeholder=\"Track ' + n + ' title\"]');
  const fileInput  = document.querySelector('#js-track-upload-' + n);
  const instrRadio = document.querySelector('#js-instrumental-radio-button-' + n);
  const performer  = document.querySelector('#track-' + n + '-performer-1-name');

  const title      = titleInput ? titleInput.value : 'MISSING';
  const fileName   = (fileInput && fileInput.files && fileInput.files.length > 0) ? fileInput.files[0].name : 'NO FILE';
  const isInstr    = instrRadio ? instrRadio.checked : false;
  const perfName   = performer ? performer.value : 'MISSING';

  const titleOK = title === expected[i].title;
  const fileOK  = fileName.includes(expected[i].file);
  const instrOK = isInstr;
  const perfOK  = perfName === 'Aslan Uzunismail';

  if (!titleOK || !fileOK || !instrOK || !perfOK) pass = false;

  results.push(
    'T' + n +
    ' title:' + (titleOK ? 'OK' : 'FAIL(' + title + ')') +
    ' file:'  + (fileOK  ? 'OK' : 'FAIL(' + fileName + ')') +
    ' instr:' + (instrOK ? 'OK' : 'FAIL') +
    ' perf:'  + (perfOK  ? 'OK' : 'FAIL(' + perfName + ')')
  );
}
results.push(pass ? '=== ALL PASS ===' : '=== FAILURES ABOVE — DO NOT SUBMIT ===');
return results.join('\n');
"
```

Also verify album-level fields:
```bash
aslan eval "
const date  = document.querySelector('#release-date-dp');
const title = document.querySelector('#albumTitleInput');
return 'date:' + (date ? date.value : 'MISSING') + ' title:' + (title ? title.value : 'MISSING');
"
```

**Fix any failures before proceeding. Do not submit with FAILs.**

---

## Phase 10 — Confirmation checkboxes

```bash
aslan click '#areyousureyoutube'
aslan click '#areyousurenonstandardscaps'
aslan click '#areyousurepromoservices'
aslan click '#areyousurerecorded'
aslan click '#areyousureotherartist'
aslan click '#areyousuretandc'
```

Take a screenshot and confirm all boxes are ticked before submitting.

---

## Phase 11 — Submit

```bash
aslan click '#doneButton'
```

Wait and check for a validation error dialog. If one appears:
- Dismiss with `.swal2-confirm`
- Read the error list carefully
- Fix each issue
- Re-run QC (Phase 9) before submitting again

---

## Phase 12 — Mixea upsell (skip)

DistroKid may redirect to `/new/mixea/` or skip Mixea and go directly to `/new/done/`. If it reaches the success page, do not look for Mixea controls. If Mixea appears, always use originals.

**Gotcha:** after submit, `aslan url` can remain `/new/` for 30–120 seconds while DistroKid accepts the release and prepares the next page. Poll URL + page text; do not treat `/new/` as failure unless a visible validation popup appears. Also, `/new/` can briefly show Mixea content before the URL changes — read page text / H1 before chasing phantom validation errors.


```bash
aslan click '.osano-cm-accept' --tab <tab_id> 2>/dev/null || true
aslan eval 'const el=[...document.querySelectorAll("input[name=variant]")].find(e=>e.value==="0"); if(!el) throw new Error("Mixea original variant radio not found"); if(!el.checked) el.click(); el.dispatchEvent(new Event("input",{bubbles:true})); el.dispatchEvent(new Event("change",{bubbles:true})); return "selected originals";' --tab <tab_id>
aslan eval 'const buttons=Array.from(document.querySelectorAll("button.submit-button, button")); const btn=buttons.find(b=>b.offsetParent!==null && !b.disabled && !String(b.className).includes("disabled") && ["Continue", "Continue with my uploaded files"].includes(b.textContent.trim())) || buttons.find(b=>b.offsetParent!==null && !b.disabled && !String(b.className).includes("disabled") && b.textContent.trim().startsWith("Continue")); if(!btn) throw new Error("Mixea continue button not found/enabled"); btn.click(); return "clicked " + btn.textContent.trim();' --tab <tab_id>
```

---

## Phase 13 — Confirm success

Success page URL contains `/new/done/` and shows:

> **Hooray, your music is on its way!**

Verify album name, year, and track count in the confirmation card.

---

## Phase 14 — Update catalog.json

After confirming success, save the `albumuuid` from the `/new/done/?albumuuid=...` URL and mark the album as `uploaded` in the catalog:

```bash
CATALOG="/Users/onorbumbum/_SITES/lofiall.day/_scripts/music/catalog.json"
ALBUM_ID="<album_id>"  # e.g. konbini-at-2am
DISTROKID_ID="<albumuuid>"
TMP="$CATALOG.tmp.$$"

jq --arg id "$ALBUM_ID" --arg dkid "$DISTROKID_ID" '
  .albums |= map(if .id == $id then
    .distrokid_status = "uploaded" |
    .distrokid_id = $dkid
  else . end)
' "$CATALOG" > "$TMP" && jq empty "$TMP" && mv "$TMP" "$CATALOG"
```

Verify:
```bash
jq --arg id "$ALBUM_ID" '.albums[] | select(.id == $id) | {id, distrokid_status, distrokid_id}' "$CATALOG"
```

**When an album later goes live (green dot on DistroKid):**

1. Navigate to its dashboard page: `https://distrokid.com/dashboard/album/?albumuuid=<uuid>`
2. Scrape the streaming links:
```bash
aslan eval "
const links = [...document.querySelectorAll('a[href]')];
const streaming = links.filter(a => a.href.includes('spotify.com') || a.href.includes('music.apple.com'));
return JSON.stringify(streaming.map(a => ({href: a.href})));
"
```
3. Update the catalog:
```bash
cat "$CATALOG" | jq --arg id "$ALBUM_ID" --arg sp "<spotify_url>" --arg am "<apple_music_url>" '
  .albums |= map(if .id == $id then
    .distrokid_status = "done" |
    .links.spotify = $sp |
    .links.apple_music = $am
  else . end)
' > /tmp/catalog-tmp.json && mv /tmp/catalog-tmp.json "$CATALOG"
```

---

## Phase 15 — Update this playbook

After every run, ask: *did anything differ from what the playbook described?*

If yes, update this file immediately while context is fresh:

| Discovery | Where to record |
|---|---|
| New DistroKid UI element or selector changed | Update the relevant Phase above |
| New failure mode encountered | Add a row to Known Failure Modes |
| New lofiall.day default confirmed | Update the defaults note in the relevant Phase |
| Step order changed | Renumber and rewrite the affected phases |

Do **not** append a log of what happened. Rewrite the step itself to reflect the correct behaviour going forward.

---

## Known Failure Modes

| Symptom | Cause | Fix |
|---|---|---|
| "Please choose a valid release date" | `aslan fill` doesn't trigger DistroKid's date validation | Use `aslan eval` with `dispatchEvent(new Event('change', {bubbles: true}))` |
| Audio files missing on submit | Parallel uploads queued but not all completed | Wait for all tmux sessions to exit; verify with eval before submitting |
| tmux capture shows blank output | Session exited before capture | Use `sleep 2` at end of tmux command; poll with `tmux ls` instead of relying on capture |
| QC eval returns all MISSING | `#doneButton` was already clicked — form is gone | Too late; check My Music page instead. Next time: QC *before* submit |
| Title input selector not found | DistroKid conditionally renders track rows | Scroll the form fully first; ensure song count is set before filling titles |
| Copy songwriter/producer shows 2 dialogs | "Do it?" + "Done!" both require `.swal2-confirm` | Click `.swal2-confirm` twice |
| Track prompts differ between songs | DistroKid conditionally shows extra radios | Read visible row after upload and answer only fields that appear |
| AI detail choices don't persist | Hidden checkboxes were changed without opening/saving the AI modal | Open `[data-js-ai-credits-open-modal][data-track="N"]`, select options inside `.swal2-popup`, then click Save |
| File appears attached but submit/upload state is wrong | Custom `DataTransfer` / localhost `fetch` injection bypassed DistroKid's normal file-input handling | Use `aslan upload <file> --selector '#js-track-upload-N'`; attach sequentially and verify `input.files` |
| New artist submits with prior artist profiles | DistroKid defaulted Spotify/Apple/YouTube/Instagram/Facebook to an existing account artist | Select visible zero-match `new` radios before submit |
| Login challenge appears | Session expired or verification needed | Ask user to handle login / email verification |
| Parallel uploads block entirely | Aslan socket + browser JS both serialize; tmux sessions all hang waiting | DO NOT use parallel tmux uploads — upload one at a time sequentially |
| Single upload times out at 120s | Browser busy processing previous track uploads to DK servers | Retry immediately with longer timeout (300s); or wait 30–60s and retry |
