# OpenRouter — Site Knowledge

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
