# Replace a Facebook Page profile photo

## Inputs

- Page URL and approved square local image.

## Prerequisites

- Logged-in account with Facebook access to the Page.
- Read `knowledge/sites/facebook.com.md`.

## Steps

1. Open the Page and read its tree. If access was recently changed, navigate to the original Page URL again to refresh the controls.
2. If viewing as the personal profile, click `Switch Now` or `Switch` and read again. Handle `Use Page` onboarding if shown, without changing notification/email preferences.
3. Click `Profile picture actions`, then `Choose profile picture`.
4. Read the dialog and inspect file inputs. Upload the approved image with `aslan upload <file> --selector '[role="dialog"] input[type="file"][accept="image/*,image/heif,image/heic"]' --tab <id>` when that exact input exists.
5. Wait for the crop editor. Screenshot it and confirm the whole centered logo fits. Leave Description blank unless copy was approved.
6. Click `Save` once and wait for the editor to close. Reload the Page and screenshot to verify the new photo persists and its circular crop is correct.

## Notes

- Tree refs change on every read. Use current refs.
- Partial/task access may hide photo editing and Page switching. Business portfolio full access is separate. Do not change permissions without approval.
- Photo menus and some dialogs render asynchronously. Read again after `Loading` rather than repeating the action.
- The upload injection worked for the profile-photo dialog in WKWebView. Check the crop preview, not just the CLI upload acknowledgement.
