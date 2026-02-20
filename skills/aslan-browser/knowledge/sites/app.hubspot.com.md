# HubSpot (app.hubspot.com)

Site-specific knowledge for HubSpot CRM.

---

## Login Flow

- Login page at `https://app.hubspot.com/login` shows "Sign in with password" button
- Clicking it reveals password field, but email is pre-filled/hidden (shows "Change email" button)
- User typically enters email before automation takes over

## Contact Profile

- Contact record URLs follow pattern: `/contacts/{portal_id}/record/0-1/{contact_id}`
- Activity feed shows all emails, notes, calls in timeline
- Each email has a "Reply" button to respond directly

## Email Composer

- Uses `contenteditable` for email body — must use `aslan type`, not `aslan fill`
- Subject field is a regular textbox that can be filled with `aslan fill`
- Dialog opens with "Reply" prefilled as "Re: {original subject}"
- Send button appears at bottom of dialog

## Navigation

- Global search available via `⌘K` or search textbox in header
- CRM menu item provides quick access to contacts, companies, deals
