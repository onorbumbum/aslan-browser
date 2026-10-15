# Facebook.com Page Knowledge

Site-specific selectors and workflows for Facebook page management.

## Post Creation Flow (Page)

To create a post on a Facebook Page:

1. Click **"What's on your mind?"** button → opens composer
2. Type content using `aslan type` (contenteditable, not `fill`)
3. Click **"Next"** button in composer
4. Click **"Post"** button in the Post Settings dialog

## Verified Element References

- Composer trigger: `button="What's on your mind?"` → `@e216`
- Composer textbox: `textbox` within dialog → `@e305` (when dialog open)
- Next button: `button="Next"` → `@e328`
- Post Settings dialog: dialog heading "Post settings"
- Final Post button: `button="Post"` in settings → `@e315`

## Joining Groups

- Navigate to `https://www.facebook.com/search/groups/?q=QUERY`, then open each group's `/groups/<id>` page. `Join group` is a `div[role=button]` whose innerText is exactly `Join group`.
- The screening-questions dialog opens only from a full pointer-event sequence (pointerdown → mousedown → pointerup → mouseup → click); a plain `.click()` on the Join button does not open it.
- "I agree to the group rules" checkboxes are hidden inputs — click the label element, not the input, or Submit stays disabled.
- Free-text question fields take `fill` normally.
- The logged-in profile in this browser is Onur's personal account ("Onor Bumbum"), which manages the We Care Medicare page.
- Space join clicks 30+ seconds apart; verified no rate limiting at that cadence (6 joins in one session).

## Page profile photo access

- Check the Page's `Admin access information` button. A `Profile Plus admin access information` menu that says `With task access, you can manage this Page with tools` means the account is not acting as the Page. The profile-photo menu may show only `View story` and `See profile picture`, with no edit action.
- Business Suite Settings → Accounts → Pages → select the Page lists its actual full and partial access assignments. Full access to the business portfolio does not imply full access to each Page.
- If the Page is absent from `Your profile` → `See all profiles` → `See more profiles`, check its access assignment before attempting photo uploads. Do not change permissions as part of a photo replacement without explicit approval.

## Page address and map pin

- While acting as the Page, open About → Contact and basic info → the address's Options → Edit address. Address visibility is a separate Public control.
- A Page with a street address can still have no coordinates. Its map editor may start at 0°, 0°. Verify the clinic's exact coordinates against a real listing, not placeholder site embeds.
- Map clicks choose a pin. The Save action can send `PagesCometEditPageAddressCoordinatesMutation` followed by `ProfileCometAddressSaveMutation`. The second mutation may geocode the address and overwrite the precise pin.
- Inspect the coordinate mutation response and verify the retained Page location independently. If the address save overwrites a successful coordinate update, repeat only the observed, authorized coordinate update after the address save completes, then verify persistence. Do not guess private mutation schemas or change permissions.
- Correct Facebook coordinates do not prove the location appears in Instagram search. Require an Instagram app test separately.

## Read-only location search diagnosis

- A Page composer may fail to open Check in in WKWebView. Switching to the personal profile can expose a different desktop composer where Location opens Search for location.
- Search uses `input[placeholder="Where are you?"]`. If `aslan type` leaves it empty or keeps stale results, use the native HTMLInputElement value setter and dispatch a bubbling input event.
- Test short, full and unaccented business names. Results can be geographically ranked, so absence in tested results is not proof of absence from Meta's entire place database.
- Searching does not require selecting a result or publishing a post. Close the empty composer when done. Never create duplicate places or publish check-ins as a diagnosis step without approval.

## Support and technical problem reports

- Business Support Home Help → Contact support can classify descriptions automatically and ask for additional details before asset selection. The initial description field has a 1000-character limit; verify that IDs and the actual issue survived truncation.
- If the issue is classified as Set up or manage store locations and only unrelated ad accounts are offered, do not select one to force a Page case. Editing the description or trying the clinic's Business Suite may still produce the same route. This is a support-routing blocker, not proof a case was opened.
- Facebook Your profile → Report a problem → Don't Include opens Report details without complete diagnostics. The form accepts Details and screenshots. A report is not a tracked support case.
- Activate React text entry and verify the text before submission. Screenshot attachments show an Uploaded screenshot thumbnail even when the file input has been cleared after processing.
- Bug-report GraphQL requests may use FormData rather than a URL-encoded string. If inspecting submission, capture the acceptance result under data.comet_report_bug from the first attempt. HTTP 200 and absence of top-level GraphQL errors do not establish acceptance. Do not repeatedly submit when acceptance is ambiguous.

## Insurance ad category policy

- Official category expansion policy at `https://www.facebook.com/business/help/510724041294968` explicitly includes insurance. US financial products and services campaigns require the category beginning January 21, 2025.
- `https://www.facebook.com/business/help/298000447747885` lists restricted age, gender, postal codes, exclusions, lookalikes and saved audiences, plus expanded city/pin radii. Verify actual allowed targeting in the account before forecasting Medicare ads.
- Meta Transparency Center policy pages may fail Toolshed extraction but render readable text in Aslan. Use `aslan text` on the loaded page.

## Notes

- The posting flow requires **two click confirmations** (Next → Post)
- Use `aslan type` for the main content textbox (contenteditable div)
- Settings dialog appears after clicking Next, with options for audience, scheduling, etc.
- The final "Post" button is only visible in the settings dialog, not the initial composer
## Joining Groups as a Page

- A Page can join groups directly. In the top-right profile switcher pick the Page (e.g. "We Care Medicare"), then use `facebook.com/groups/discover` (suggestions + Your groups) or `/search/groups/?q=QUERY` — both show working `Join`/`Join group` buttons while acting as the Page. Private groups open the same screening-question dialog; answer and Submit.
- Leaving groups as a profile: click the `Joined` button → menu (`Manage notifications` / `Unfollow group` / `Leave group`) → `Leave group` → confirm dialog `Cancel`/`Leave group`. Pending requests: `Cancel request` button reverts straight to `Join group`.
- Page group surface verified 2026-10 for We Care Medicare (page 863919916794925): 5 instant joins + 2 pending requests in one session, 30s spacing, no rate limiting.

## Page settings URLs (new Pages experience, acting as the Page)

- Page setup (name, **Page type: Business/Creator**, status, recommendation): `/settings/?tab=pages`. Meta auto-assigned Page type in Dec 2025; a local business can end up as `Creator`. Switching is limited to once every 7 days.
- Page status (restrictions): `/settings/?tab=profile_quality`. Recommendation status: `/settings/?tab=profile_recommendations`. Guessed tab names like `profile_status` show "This page isn't available right now".
- Change log: `/settings/?tab=profile_management_history`. It does not list every edit (address/pin edits and some renames are missing).
- Linked Instagram/WhatsApp: `/settings/?tab=linked_profiles`.
- Real Page URL from a dead vanity link: Google `"<name>" site:facebook.com` returns `profile.php?id=...` URLs. `/search/pages` and `/search/places` may not return a Page at all even when it is published; treat absence there as a symptom, not proof the Page is missing.
- Changing Page type: the `Page type` row on `/settings/?tab=pages` ignores `aslan click`; dispatch the full pointer-event sequence on the div whose text starts with "Page type". In the dialog, `aslan click` on the option's wrapper node selects the radio (verify with `input[type=radio]` `.checked`), then pointer-event `Next` → `Confirm`. The Confirm eval may return "JavaScript error" because the dialog unmounts; reload the tab and read the `Page type…` button label to verify. No cost; the category and address are preserved.
- Graph API place check (toolshed Meta token at `~/.config/toolshed/connections/meta/accounts/onur/token.json`): `/<page-id>?fields=location,place_type,can_checkin,checkins`. `place_type: PLACE` + `can_checkin: true` + lat/lng means Facebook's data is right; consumer search (`/search/places`, the Business Suite composer Location picker, Instagram) can still lag days behind it.
- Business Suite composer Location picker (`business.facebook.com/latest/composer?asset_id=<page-id>` → `Location` button): type with `execCommand("insertText")` on `input[aria-label=Location]`, read `[role=option]`. Close with Cancel; nothing publishes.
