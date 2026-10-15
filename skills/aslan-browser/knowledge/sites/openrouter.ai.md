# OpenRouter — Site Knowledge

## Key rotation

- `/settings/keys` redirects to `/workspaces/default/keys` after login. Google social login can complete using an existing browser session.
- Key row checkbox labels contain the SHA-256 of the full API key. Match that hash locally before opening the row's `button[aria-label="Row actions"]`, then choose Delete and confirm.
- New Key requires an explicit expiration and credit limit. Preserve the old key's policy when replacing it.
- The name input may show a DOM value without updating React state, leaving Create disabled. If normal fill/type and native setter events fail, inspect the input's current `__reactProps*` and deliver its observed `onChange` handler an event with `target.name` and `target.value`.
- New key dialog has `button[aria-label="Copy key to clipboard"]`. Capture `pbpaste` directly into a private file without printing it, verify its format, then clear the clipboard.
- Verify deletion through `/api/v1/key` and `/api/v1/credits` returning 401. Legacy `/api/v1/auth/key` may still return 200 after deletion.

## Auth Modal

- "Sign Up" button in top nav opens the **create account** modal.
- "Sign in" link at bottom of that modal switches to the **sign in** modal.
- Use "Sign in" for existing accounts — "Sign Up" triggers a Cloudflare captcha after social button click.

## Social Login Buttons

- Three unlabeled buttons at top of both modals. No accessible names — all show as `button ""` with `img ""`.
- Order (left to right): **GitHub**, **Google**, **Metamask**.
- Identify by position or screenshot. Google is always the middle button.

## OAuth Popup Flow

- Clicking a social login button opens an OAuth popup (e.g., Google).
- The popup is transient — it does NOT appear as a tab in `aslan tabs`.
- After user authenticates in the popup, it closes and the parent page redirects to logged-in state.
- Profile avatar appears in top-right corner when logged in.
