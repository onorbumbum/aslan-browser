# Site: social.zoho.com (Zoho Social)

Social media management dashboard. Posts to all connected channels simultaneously.

## Account

- Email: `onur@uzunu.com`
- Brand: "Uzunu"
- Direct URL: `https://social.zoho.com/social/onur/1640293000000023017/Home.do#home`
- Plan: Free Edition

## Connected Channels (5)

| Channel | Platform | Account Name |
|---|---|---|
| Facebook Page | Facebook | Uzunu |
| LinkedIn Profile | LinkedIn | Onur Uzunismail |
| LinkedIn Company | LinkedIn | Uzunu |
| Instagram | Instagram | heyuzunu |
| Google Business | Google | (YouGrow/Uzunu) |

## Authentication

- Login: email + password + TOTP (6-digit authenticator)
- "Trust device" persists cookies for extended sessions
- Login URL: `https://accounts.zoho.com/signin?servicename=ZohoSocial&signupurl=https://www.zoho.com/social/signup.html`

## UI Architecture

- Heavy use of **web components** (custom elements like `zs-content-editor-textarea`, `zs-newpost-composer`, etc.)
- Content editor is a `contenteditable` div inside nested web components
- Key composer selector: `#content-editor-newpost-content-editor-div`
- Media picker file input: `INPUT#np-browsemedia`
- Post button: `BUTTON#newpost-composer-footer-publish-button`
- Media button: `A#zs-newpost-composer-footer-option-media`
- Attach button in media picker: `BUTTON#mediaAttachButton`
- New Post header button: `SPAN.zs-header-rhs--links_newbtn__post__txt`

## Gotchas

- Instagram frequently shows a red error ring on its avatar in the composer — may be token/auth flaky. Usually still posts fine.
- After clicking "Post Now", a Publishing Progress panel appears at bottom-right showing per-channel status. Instagram is consistently the slowest (30-60s).
- WebP images may be rejected by some channels — always convert to JPEG before uploading.
- URL link previews auto-generate when a URL is in the post body. Takes a few seconds.
- Facebook thumbnail previews are "automatically generated and can't be customized" per the UI note.
