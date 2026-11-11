# Acuity Scheduling

## Calendar name

- Availability → Calendars → Calendar Settings controls the public "with ..." label. Renaming a calendar affects every appointment type on that calendar, so confirm scope first.
- The name field is `input[placeholder="Add name..."]`. Aslan fill may update its visible value without updating React state. Use the native `HTMLInputElement.prototype.value` setter and bubbling `input`/`change` events, save, and verify the public booking page.
- Village Creative's busking calendar is ID 5497109, now named Village Creative. Do not change booking-notification or reply-to addresses when renaming.

## Busking classes

- Village Creative's account owner ID is 22910069. The public scheduling page is `https://app.acuityscheduling.com/schedule.php?owner=22910069`.
- Existing busking appointment types are twelve separate 10-minute group classes named by start time, from 12:00 through 1:50. Reuse these rather than creating duplicate services. Each type has `#group_max` set to 1.
- Offer Class opens an asynchronous dialog. Wait for `#date-input` before filling it. The type dropdown is `select[name="type"]`, time is `#time`, and submit is `input[value="Save Class"]`.
- Typing `#date-input` may leave hidden `input[name="date[]"]` empty. Select the datepicker's `[aria-label="M/D/YYYY"]` day and verify the hidden date before saving.
- Wait for the explicit `Successfully added ...` message after saving before opening the next Offer Class dialog. An early click can be lost during navigation.
- When offering a different type from the dropdown, the underlying page can remain on the original type. Its class list does not verify the newly selected type. Open that type's edit page or check its public page.
- Public booking asks for first name, last name, and email. Phone is optional in the current Village Creative setup. No extra intake form is configured.
- Do not confirm a test appointment without approval. Inspect the public selection and information steps without pressing Confirm Appointment.

## Appointment export

- Reports → Import/Export has Export to Spreadsheet (.csv), with a from/to date range and an optional Include canceled appointments checkbox.
- Datepickers use `#minDay-input` and `#maxDay-input`. Select a day and verify hidden `minDay` and `maxDay` hold ISO dates before exporting.
- The visible appointment export form POSTs to `/appointments.php?action=exportExcel`. A scoped read-only export can use `fetch(form.action, {method: "POST", body: new FormData(form), credentials: "same-origin"})`. Keep CSRF fields in browser memory.
- A date range with no appointments can return HTTP 200 and an attachment named `scheduleYYYY-MM-DD.csv` with an empty body and no header. That alone does not verify the column schema. Do not create a booking solely to populate an export without approval.
