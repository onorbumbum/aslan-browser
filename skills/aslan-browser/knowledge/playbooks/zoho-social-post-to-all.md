# Playbook: Post to All Socials via Zoho Social

Post a blog article (or any content) to all connected social channels at once using Zoho Social. Currently connected channels: Facebook (Uzunu), LinkedIn Profile (Onur Uzunismail), LinkedIn Company Page (Uzunu), Instagram (heyuzunu), Google Business Profile.

## Inputs

- **post_json_path**: path to the blog post JSON file (e.g. `posts/wix-not-working-real-options.json`)
- **copy**: string — the social media copy text, including the blog URL. If not provided, generate it using the blog post content + YouGrow voice conventions.
- **image_path**: path to the featured image (from post JSON `featured_image` field, resolved against the site's `public/` directory). Usually `.webp`.

## Prerequisites

- Zoho Social account: `onur@uzunu.com`
- Login requires password + TOTP (6-digit authenticator code). User must handle MFA manually if needed.
- If already logged in (cookies persist after "Trust" device), login is skipped.

## Steps

### 0. Prepare the image

Featured images are `.webp` — some social platforms (Instagram, GMB) reject webp. Convert to JPEG first:

```bash
sips -s format jpeg {image_path} --out /tmp/zoho-social-upload.jpg
```

Verify the output file exists and is non-zero bytes.

### 1. Create the social copy

Read the blog post JSON and craft a single copy that works across all platforms (LinkedIn, Facebook, Instagram, Google Business).

1. Read the post JSON — extract title, excerpt, key points, blog URL
2. Read `docs/conventions.md` and `docs/yougrow-strategy.md` for voice/tone
3. Write copy that:
   - **Leads with the reader's frustration or question** (hook — pull them in)
   - **Describes what the blog covers** (value — why click)
   - **Ends with the blog URL** on its own line (no emoji prefix — user hates 👉)
   - Stays under 500 characters (Google Business Profile is the most restrictive)
   - Uses YouGrow voice: conversational, direct, zero fluff, no jargon
   - No hashtags unless explicitly requested
4. **Present the copy to the user for approval** before proceeding — offer 2 options (e.g. "lead with frustration" vs "lead with helpfulness")
5. User picks one (or asks for tweaks) → finalize

### 2. Navigate to Zoho Social

```bash
aslan nav "https://social.zoho.com/social/onur/1640293000000023017/Home.do#home" --wait idle
```

- If redirected to login page (`accounts.zoho.com/signin`): perform login (see Login section below)
- If landed on dashboard with "Recent Posts" section: already logged in, proceed

### 3. Click "New Post"

- Look for `SPAN.zs-header-rhs--links_newbtn__post__txt` containing "New Post" in the top header
- `aslan click "span.zs-header-rhs--links_newbtn__post__txt"`
- Wait for the composer to load: `aslan wait --idle`
- Verify: `aslan tree` should show the contenteditable composer div

### 4. Verify all channels are selected

- The composer header shows channel avatars with network icons (Facebook, LinkedIn, LinkedIn Company, Instagram, Google)
- All should be pre-selected by default
- If any show a red ring / error indicator (especially Instagram): click the `×` on the errored channel to deselect, then re-click to re-select. If still errored, proceed without it and note in output.

### 5. Enter the copy text

The content editor is a **contenteditable div** (not an input/textarea):

```
Selector: #content-editor-newpost-content-editor-div
Placeholder: "It's a beautiful day to create..."
```

Use `aslan type`:
```bash
aslan type "#content-editor-newpost-content-editor-div" "{copy_text}"
```

- Verify: `aslan tree` or `aslan text` should show the pasted copy
- The URL in the copy will auto-generate a link preview card below the text (shows blog title, excerpt, thumbnail). Wait a few seconds for it to load.

### 6. Attach the featured image

**This is fully automated — no manual user intervention needed.** `aslan upload` injects the file directly via DataTransfer API.

Click the media/image icon in the composer footer:
```bash
aslan click "#zs-newpost-composer-footer-option-media"
```

Wait for the media picker dialog to appear:
```bash
aslan wait --idle
```

If the media picker shows a previously selected image from a prior session, remove it first (click the × on the thumbnail at the bottom of the picker) before uploading.

The media picker shows a "Desktop" tab with a file input (`INPUT#np-browsemedia`). Upload the converted JPEG:
```bash
aslan upload /tmp/zoho-social-upload.jpg --selector "#np-browsemedia"
```

Wait for upload to process, then click "Attach":
```bash
aslan wait --idle
aslan click "#mediaAttachButton"
aslan wait --idle
```

Verify: the composer should now show the image thumbnail at the bottom of the post area.

### 7. Post Now

Click the publish button:
```bash
aslan click "#newpost-composer-footer-publish-button"
```

### 8. Wait for publishing to complete

After clicking "Post Now", a **Publishing Progress** panel appears at the bottom-right showing each channel's status (e.g. "Uzunu: Post is in progress." → "Uzunu: Posted successfully.").

The panel shows `N/5` progress counter. Poll until all 5 are done:

```bash
# Wait a few seconds, then check
sleep 3
aslan tree
```

Look for the progress panel text. Repeat checking every 5 seconds until:
- All channels show completion, OR
- Progress counter shows `5/5`
- Instagram is typically the slowest — may take 30-60 seconds

### 9. Verify

Check the "Recent Posts" section on the dashboard to confirm new posts appear for all channels. Take a screenshot for confirmation:
```bash
aslan shot /tmp/zoho-post-result.jpg
```

## Login (if needed)

Only required when cookies have expired.

1. On the login page, fill email:
   ```bash
   aslan fill "#login_id" "onur@uzunu.com"
   ```
2. The password field appears after email is submitted — fill will need to happen after Next is clicked. **ASK THE USER** for the password or to paste it manually.
3. After password, click "Sign in" (`BUTTON#nextbtn`)
4. MFA TOTP screen appears — **ASK THE USER** to enter the 6-digit code from their authenticator app
5. After TOTP verification, a "Trust this device?" prompt may appear — click "Trust" (`BUTTON.trustdevice`)
6. Should redirect to Zoho Social dashboard

## Known Issues

| Symptom | Cause | Fix |
|---|---|---|
| Instagram shows red ring error | Token expired or API issue | Deselect and re-select. If persists, post without IG and note it. |
| Image upload fails silently | WebP format rejected | Always convert to JPEG first (step 0) |
| Link preview doesn't load | URL not yet crawled by Zoho | Wait 5-10 seconds. If still missing, proceed — some platforms still fetch it on publish. |
| Content editor doesn't accept type | Shadow DOM / web component | Use `aslan eval` to set innerHTML directly on `#content-editor-newpost-content-editor-div` |
| "Post Now" button grayed out | Missing required field or channel error | Check all channels are valid (no red rings). Ensure text is non-empty. |
| Publishing hangs on one channel | Platform API rate limit or auth issue | Wait up to 2 minutes. If one channel fails, others usually succeed. Note the failure. |
