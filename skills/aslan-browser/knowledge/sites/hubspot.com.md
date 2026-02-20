# HubSpot (hubspot.com)

## Navigation
- Login URL: `https://app.hubspot.com/login`
- Home URL: `https://app-na2.hubspot.com/global-home/` (Region may vary)

## Selectors & Interaction
- **Login Flow**:
  1. Enter email in `textbox "Email"` (or `input[type="email"]`).
  2. Click `button "Continue"`.
  3. Enter password in `textbox "Password"` (appears after clicking Continue).
  4. Click `button "Log in"`.
- **Navigation**:
  - Global Search: `textbox "Search HubSpot"` (Shortcut: `Cmd+K`).
  - Top Nav: `menuitem "Settings"`, `button "View profile and more"`.
  - Sidebar: `menuitem "CRM"`, `menuitem "Marketing"`, `menuitem "Sales"`, etc.

## Tips
- HubSpot is a heavy SPA. Always use `aslan wait --idle` after navigation or clicking main menu items.
- The login process sometimes triggers "New Device" verification via email.
