# hunter.io

## Prefer the V2 API for sequence automation

- Hunter's V2 API supports CRUD for email sequences, follow-ups, recipients, leads, lead lists, custom attributes, templates, and API keys.
- It also exposes read-only email-account discovery, health, usage, capacity, warmup, and sequence-dependency endpoints.
- Use the browser only for login, API-key setup, and final UI verification when API automation is available.
- Sequence states include `draft`, `planned`, `active`, `paused`, and `archived`. Build in `draft`; never call the start endpoint without explicit user approval.
- The legacy sequence path uses `/v2/campaigns`; newer endpoints are also documented under the Email Sequences section. Check the current official API reference before implementing because some endpoints are Beta.
- Adding recipients to an active sequence may send quickly. Confirm the sequence is draft before recipient mutations.
- Hunter requires merge-tag fallbacks in API-created templates, for example `{{first_name|fallback:"there"}}`.

## UI orientation

- Main navigation: `Sequences`.
- Sequence sub-navigation includes `All sequences`, `Inbox`, `Engagement`, `Reporting`, `Queue`, `Email accounts center`, `Settings`, `Templates`, and `Unsubscriptions`.
- `Email accounts center` shows sender status, warmup protection, daily limits, scheduled volume, health, domain issues, and account details.
