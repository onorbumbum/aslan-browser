# DistroKid — Site Knowledge

## Login

- Homepage sign-in trigger: `#signInButtonFrontPage`
- Sign-in form fields:
  - email: `#inputSigninEmail`
  - password: `#inputSigninPassword`
  - submit: `#signinButton`
- DistroKid often keeps the session alive after a successful sign-in. If already logged in, go straight to `https://distrokid.com/mymusic/`.
- If a verification challenge appears, expect email-based verification and pause for user help.

## Upload Entry Point

- Logged-in library page: `https://distrokid.com/mymusic/`
- Upload button on library page: `.button-blue[href="/new/"]`
- Album upload form lives at: `https://distrokid.com/new/`

## Stable Album-Level Selectors

- song count: `#howManySongsOnThisAlbum`
- release date: `#release-date-dp`
- primary genre: `#genrePrimary`
- primary subgenre: `#subGenrePrimary`
- secondary genre: `#genreSecondary`
- secondary subgenre: `#subGenreSecondary`
- artwork file input: `#artwork`
- album title: `#albumTitleInput`
- continue/upload button: `#doneButton`

## Stable Track-Level Selectors

- audio upload input for track N: `#js-track-upload-N`
- instrumental yes radio for track N: `#js-instrumental-radio-button-N`
- title field is easiest to target by placeholder, e.g. `input[placeholder="Track 1 title"]`
- Track title IDs are UUID-like and not reusable across releases.
- Songwriter fields are easiest to fill on track 1, then copy to all tracks using `#js-copy-songwriters-link-1`.

## Credits / Apple Music Requirements

- Open credits accordion: `.requirements-item-title`
- Track 1 performer role: `#track-1-performer-1-role`
- Track 1 performer name: `#track-1-performer-1-name`
- Copy performer to all tracks: `#copy-performer`
- Track 1 producer role: `#track-1-producer-1-role`
- Track 1 producer name: `#track-1-producer-1-name`
- Copy producer to all tracks: `#copy-producer`
- Copy actions open SweetAlert confirmations; confirm with `.swal2-confirm`

## New Artist Profile Options

- When uploading a new artist's first release under an account that already has other artists, DistroKid can default visible Spotify/Apple/YouTube/Instagram/Facebook questions to the prior artist profile.
- Choose the visible `new` / zero-match options for a first release:
  - Spotify: `#js-spotify-artist-id-zero-matches-new`
  - Apple Music: `#js-apple-artist-id-zero-matches-new`
  - YouTube Music: `#js-google-artist-id-zero-matches-new`
  - Instagram: `#js-instagramProfile-artist-id-zero-matches-new`
  - Facebook: `#js-facebookProfile-artist-id-zero-matches-new`
- Do not click hidden fallback radios like `#spotifyNoArtistIDFirst` if the visible zero-match option exists; same-name radio groups can uncheck the visible choice.

## AI Disclosure

- AI gate radios have track attributes, e.g. `input[name^="ai_gate_"][track="1"][value="1"]` for Yes.
- DistroKid only persists AI detail selections after opening the per-track modal with `[data-js-ai-credits-open-modal][data-track="N"]`, selecting options in `.swal2-popup`, and clicking `.swal2-confirm` / `.ai-modal-btn-save`.
- Setting hidden detail checkboxes directly is not enough.
- Useful modal selectors:
  - Music composed by AI: `.swal2-popup input.distroAiMusic`
  - Lyrics written by AI: `.swal2-popup input.distroAiLyrics`
  - All audio performed by AI: `.swal2-popup input.distroAiRecordingScope[value="full"]`
  - Partial audio performed by AI: `.swal2-popup input.distroAiRecordingScope[value="partial"]`
  - Human artist/group: `.swal2-popup input.distroAiArtistPersona[value="0"]`
  - AI persona: `.swal2-popup input.distroAiArtistPersona[value="1"]`

## Mandatory Final Checkboxes

- YouTube checkbox: `#areyousureyoutube`
- non-standard caps checkbox: `#areyousurenonstandardscaps`
- promo services checkbox: `#areyousurepromoservices`
- recorded by you checkbox: `#areyousurerecorded`
- not another artist checkbox: `#areyousureotherartist`
- terms checkbox: `#areyousuretandc`

## Post-Submit Behavior

- After clicking `#doneButton`, DistroKid waits for all uploads to finish before moving on. This can take a long time on large albums. During this state the button may be disabled with text `Uploading...`; wait rather than treating it as a validation failure.
- The URL may remain exactly `/new/` for 30–120 seconds after submit while DistroKid accepts the release; do not treat `/new/` as a redirect or immediate failure unless a visible validation popup appears.
- A Mixea upsell can appear at `/new/mixea/` after that delay.
- To skip Mixea and keep original masters:
  - use JS eval to select `input[name="variant"][value="0"]` and dispatch `input`/`change`; `aslan click` on this radio can throw a JavaScript error even when the element is visible
  - accept/dismiss the cookie banner first with a separate `aslan click '.osano-cm-accept' 2>/dev/null || true`; don't click it from inside the same page JS eval, because Osano/DistroKid handlers can throw and abort the eval
  - click the visible enabled button whose text is `Continue` (or `Continue with my uploaded files`); don't blindly click `button.submit-button` because the Mixea page can contain multiple submit buttons, including disabled/hidden ones.
- Success page URL pattern: `/new/done/`
- Success page marker: `H1` with `Hooray, your music is on its way!`

## lofiall.day Defaults Captured In This Session

- song count varies per album
- release date: use today's date when publishing immediately
- genre defaults used in this recording:
  - `#genrePrimary` = `9`
  - `#subGenrePrimary` = `36`
  - `#genreSecondary` = `9`
  - `#subGenreSecondary` = `40`
- songwriter/composer for all tracks: `Aslan Uzunismail`
- lofiall.day albums are instrumental by default
- Apple Music credits used in this recording:
  - performer role: `Other instrument`
  - performer name: `Aslan Uzunismail`
  - producer role: `Producer`
  - producer name: `Aslan Uzunismail`
