# Create and authorize a direct Meta publishing app

## Inputs

- A neutral app display name, for example `Toolshed Social`.
- The user's own owner business portfolio and contact email.
- A Toolshed connection name.
- Private local paths for the main app client file and temporary token files.

## Prerequisites

- Signed-in Meta developer session in Aslan.
- Permission to create the app and request Facebook Page/linked Instagram publishing access.
- Existing `toolshed meta` installation. Read `toolshed meta --help` and its publishing contract.

## Interactive steps

Read the page after every action. Do not run this as a preplanned multi-step browser script.

1. Open `https://developers.facebook.com/apps/` in a pinned Aslan tab. Inspect existing apps and get a deliberate app choice before changing an existing integration.
2. Choose Create App. Enter the neutral display name and the user's contact email. Meta rejects brand words including `meta` in display names.
3. Verify the displayed character counter changed, not just the textbox DOM value. See the site knowledge for React input handling when ordinary fill/type is ignored.
4. Under Content management, select `Manage messaging & content on Instagram` and `Manage everything on your Page`.
5. Select the intended owner portfolio, not a client's portfolio. Review the overview before Create app.
6. If Meta requests password confirmation, pause for the user. Confirm creation by the new app dashboard and app ID, not by the prior button click.
7. In the Page use case's permissions table, add `pages_manage_posts` and `pages_read_engagement`. Verify `pages_show_list` is available. A shared permission can open an additional confirmation dialog listing the affected use case. Confirm only the newly created app's intended use cases.
8. In the Instagram use case's Permissions and features table, add `instagram_basic` and `instagram_content_publish`. Do not select the separate `instagram_business_*` login route for linked Facebook Pages. `business_management` may already be present through the use-case templates.
9. Keep HTTPS enforcement and strict redirect matching enabled. A pending URI textbox is not evidence that an OAuth redirect was saved. Use the validator or reload to check it. The access-token import route below does not need a registered local callback.
10. Open main App settings > Basic. Use the main app ID and app secret, not the separate Instagram-login app credentials. Click Show only when authorized; pause for the user's password confirmation if asked.
11. After revealing the secret, never dump the page, tree, or screenshot. Read only safe booleans/labels until capture. Use `aslan eval` returning `JSON.stringify({app_id,app_secret,...})` with stdout redirected directly to a new private local file under umask 077. Validate without printing its contents. Directories must be 0700, credential files 0600. Never overwrite an existing credential file blindly.
12. Navigate away from the revealed secret. Open `https://developers.facebook.com/tools/explorer/<MAIN_APP_ID>/` and verify the selected app name.
13. Select the publishing permissions in Graph API Explorer. Pages permissions are under `Events Groups Pages`; linked Instagram permissions are under `Other`. The permission menu can stay open after each selection. Read the selected permission chips to verify additions.
14. Request a User access token with Generate Access Token or Get Token > Get User Access Token. Do not select a Page or App token. Only request needed scopes. For the linked-business route, the tested set is `pages_show_list`, `pages_read_engagement`, `pages_manage_posts`, `instagram_basic`, `instagram_content_publish`, and `business_management`.
15. The authorization popup may be visible to the user without appearing in `aslan tabs`. Let the user finish consent if Aslan cannot target it. Verify `User Token`, selected permissions, and whether the Access Token input is nonempty. Never print that input value.
16. Capture the user token into a private bootstrap JSON file containing exactly `access_token`, again redirecting `aslan eval` stdout instead of exposing it in tool output.
17. For durable use, explicitly exchange the bootstrap token at Meta's documented `/oauth/access_token` endpoint using `grant_type=fb_exchange_token`, the local app credentials, and the bootstrap token. Do not log the response or credential-bearing URL. Save only the returned access token into a new private grant file. Toolshed's import command does not perform this exchange implicitly.
18. Run `toolshed meta --connection <name> account import --client-file <private-client-file> --token-file <private-grant-file>`. The tool validates app/user identity, scopes, and expiry before storing the connection.
19. Run account status and accounts. Check pagination rather than assuming a single response is complete. Optional read-only smoke checks are Page posts, linked Instagram media, and the Instagram publishing-limit read. Do not prepare or publish a live post without an approved target and content.
20. Once account status validates the stored grant, remove the temporary bootstrap and grant copies. Retain the client file for later reauthorization. Check final credential modes. Navigate away from the token screen to the unpublished app dashboard.
21. Report the named connection, discovered Page/Instagram counts, actual read verification, token expiry, and any blockers. Explicitly state that no posts were published. Do not claim successful posting based on reads alone.

## Limits

- Do not publish the app, submit App Review, rotate secrets, or modify other apps during this setup.
- Development-mode grants can work for app-role users without proving production access for unrelated users.
- Long-lived user tokens still expire; preserve the expiry returned by Meta and plan explicit reauthorization.
- Never ask the user to paste their password, app secret, or access token into chat.
