# Meta developer dashboard

## App selection and use cases

- `https://developers.facebook.com/apps/` lists apps for the signed-in developer. Inspect the existing app and select it deliberately before changing settings; a posting setup does not authorize altering unrelated integrations.
- Migrated apps show a "Your app has a new home on the social technologies developer center" dialog. "Skip" dismisses the tour without changing app configuration.
- "Use cases" lists configured capabilities. "Customize" on "Manage messaging & content on Instagram" opens its API setup and permissions pages.
- Instagram has separate "API setup with Instagram login" and "API setup with Facebook login" pages. Linked Facebook Page workflows use the latter.
- The Instagram-login page displays a separate Instagram app ID and Instagram app secret. Do not use those as the main Meta app credentials for Facebook Login.
- "Facebook Login for Business" has Settings and Configurations sections. App settings has Basic and Advanced sections. Read current settings before saving anything.
- Do not publish the app, submit App Review, rotate secrets, or change portfolio ownership as a side effect of credential inspection.

## App creation

- Meta rejects app names containing its brand terms, including "meta". Use a neutral display name such as "Toolshed Social"; the local CLI name can remain `meta`.
- Under Content management, choose "Manage messaging & content on Instagram" and "Manage everything on your Page" for linked Page publishing. Additional messaging, ads, or live-stream use cases are not needed for this posting task.
- App creation asks for a business portfolio. Use the explicitly chosen owner portfolio, not a client's portfolio simply because it appears in the list.
- The final "Create app" can trigger a "Please re-enter your password" dialog. Pause for the user to confirm in the browser. Do not report the app as created while that confirmation is pending.

## Browser handling

- Pin the developer tab on each command. The installed CLI expects tab flags after the subcommand, for example `aslan tree --tab tab2`, not before `tree`.
- Allow SPA navigation to finish and reread text/tree if the first read contains only the navigation shell.
- App creation's React textboxes can show a changed DOM value while React still has the old value. Check the character counter before advancing. If fill/type and native setter events do not update it, obtain the input's `__reactProps$...` property and call its existing `onChange` handler with `target` and `currentTarget` pointing to that input, then reread the page. Keep this scoped to the observed input.
- Graph API Explorer can preload an Access Token input. Never dump its tree or input/label HTML, since the token can appear in value attributes. Use page innerText and narrowly scoped non-secret metadata instead.
- Adding the Marketing API use case enables `ads_management` and `ads_read` for testing. Add `pages_manage_ads` separately for Page-associated ads. A regenerated user grant still needs consent and verification; use-case configuration alone does not expand an existing token.
- Secret fields may be rendered as masked textboxes with a "Show" control. Never dump the page/tree after revealing a secret; capture it directly into a private local credential file without printing its value.
