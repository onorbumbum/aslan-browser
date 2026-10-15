# app.netlify.com

Onur's Netlify account is `onur-7oq3aaq's team` (user onur@uzunu.com, already logged in inside Aslan).

## Changing the production branch / branch deploy settings

The public API (`netlify api updateSite`) silently ignores `build_settings.repo_branch` and `allowed_branches`; these can only be changed in the UI.

1. Navigate to `https://app.netlify.com/projects/<name>/configuration/deploys` (redirects to Developer settings).
2. Left sections nav: click "Branches and deploy contexts".
3. Click its "Configure" button — an inline form opens with `input[name="repo_branch"]` (Production branch) and `name="allowed_branches"` radios (All / None / Choose individually / production-only).
4. Save button is `@e130`-style ref near Cancel; refs change, re-read the tree.

### React input gotcha (critical)

`aslan fill` sets the DOM value but Netlify's React app keeps its own state, so Save silently saves the OLD value. Use the native setter + input event instead:

```bash
aslan eval "
const input = document.querySelector('input[name=\"repo_branch\"]');
const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
setter.call(input, 'main');
input.dispatchEvent(new Event('input', { bubbles: true }));
return input.value;
"
```

Verify success via the API afterwards: `netlify api getSite --data '{"site_id": "..."}'` → `build_settings.repo_branch`.

## esmasonmezcom project

- Repo `onorbumbum/esmasonmezcom`, publishes committed `dist/` with empty build command.
- Production branch `main` since 2026-10-14; every push to main auto-deploys.
- `esmasonmez.com` is NOT attached to this project (staging only, see site AGENTS.md).
