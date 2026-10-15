# Google Business Profile — Site Knowledge

## Duplicate-profile merge support

- Start at `https://support.google.com/business/gethelp?hl=en`, select the profile to retain, describe the merge, then choose `Merge profiles` and proceed to email contact.
- The contact flow may display an unrelated existing support case before Resources. Read its product and context; do not treat that case ID as the newly requested merge case.
- The accessibility tree includes hidden Email statuses such as Closed and Unavailable. Verify the button's actual visible text and disabled state before declaring support unavailable.
- The email form is inside a same-origin iframe at `/s/renderframe2/`. Inspect each iframe's `contentDocument.body.innerText` to find the populated form. Navigating directly to the bare iframe URL would lose its injected form context.
- Form field names include `name`, `customer_email`, `relationship_to_biz`, `business_name`, `business_address`, `business_nmx_id`, `problem_page`, `duplicate_business_link`, and `describe_issue`. An agency representative uses `relationship_to_biz=agency`.
- A callback phone is required. The registration/license/tax certificate and matching utility-bill uploads are requested in the form, but do not display required-field stars. Do not infer they are mandatory or invent evidence. Verify actual validation on an authorized submission.
- Submission is not established by filling the form or by an existing case ID. Verify a new confirmation and case ID after one submit action.
- After a reported merge, inspect both original Maps links and Business Profile Manager rows. Separate managed profiles can keep different titles but link to the same public CID; the public title can still differ from the requested retained name. Both rows may require verification. Follow support's specific instruction about which profile to verify, not both automatic verification emails. Empty API review lists during unverified management do not prove public reviews were deleted.

## Photo upload navigation

- Business Manager rows expose exact Add photo URLs at `https://business.google.com/n/{locationId}/photos/add?fid={cid}`. If a link click does nothing, inspect its href and navigate explicitly in the owned tab.
- This redirects to Google Search with `#mpd=~{locationId}/promote/photos/add`. A simplified Search page can omit all merchant controls and iframes. Inspect actual DOM before attempting an upload.
- Observed with a bare WKWebView UA ending in `AppleWebKit/605.1.15 (KHTML, like Gecko)`. Do not change global browser settings during concurrent work. The CLI has no documented user-agent command.
- Business Manager row status can reveal Suspended even while the Business Information API reports `openInfo.status: OPEN`.

## Photo uploader access

- Business Manager's `Add photo` link uses `target="_blank"`. Inspect the exact business row's href and navigate it in your own tab if the click does not create a tab.
- Current links redirect to Google Search with a `#mpd=~LOCATION_ID/promote/photos/add` fragment. The simplified Search page does not render these owner controls.
- Check `navigator.userAgent` when only plain search results appear. A build reporting bare `AppleWebKit/605.1.15` without a Safari/Chrome version received simplified Search; adding `gbv=2` did not restore the uploader. Do not assume auth failure or claim photo upload succeeded.
- Maps may show a `Manage your Business Profile` link while `Add photos & videos` fails to open an uploader. Verify dialog/iframe presence before calling `aslan upload`.

- With the full Google UI loaded, extract the iframe URL containing `/local/business/{locationId}/promote/photos/add` and navigate directly in the owned tab. The hidden `input[type=file]` is already present.
- `aslan upload` immediately submits the photo without a second publish button. Wait until Upload complete and return to Photos and videos before clicking Add photos for the next file. Do not retry during Uploading.
- Uploaded photos can appear with PENDING badges. Reload the gallery to verify persistence; upload completion does not establish public approval. This flow offers no caption field.

## Post Creation

- The "Create post" modal is an embedded iframe
- Cannot interact with it from the parent page — extract the iframe `src` and navigate directly to it
- Image uploads require JPG or PNG — WebP silently fails
  - Convert with: `sips -s format jpeg input.webp --out output.jpg`

## Call to Action Buttons

To add a CTA button (e.g., "Learn more"):

1. Click "Add link fields" button
2. Click the dropdown (defaults to "None")
3. Select desired option by matching `innerText` in the Material dropdown
4. A URL input field appears — find the last `input[type="text"]` or `input[type="url"]`
5. Set value and dispatch `input` + `change` events
