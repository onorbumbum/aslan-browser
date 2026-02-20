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

## Notes

- The posting flow requires **two click confirmations** (Next → Post)
- Use `aslan type` for the main content textbox (contenteditable div)
- Settings dialog appears after clicking Next, with options for audience, scheduling, etc.
- The final "Post" button is only visible in the settings dialog, not the initial composer