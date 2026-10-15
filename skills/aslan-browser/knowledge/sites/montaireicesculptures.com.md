# montaireicesculptures.com

## Contact form test lead

Use the live contact page:

```bash
aslan nav https://www.montaireicesculptures.com/contact.html --wait idle
```

Useful selectors:
- `#quote-fname`
- `#quote-lname`
- `#quote-email`
- `#quote-phone`
- `#quote-billing_name_and_address`
- `#quote-event_date`
- `#quote-venue_name`
- `#quote-venue_address`
- `#quote-guests_walk_in_time`
- `#quote-message`
- `input[value="General Contact"]`
- submit button appears in tree as `Send Message`; CSS submit works via `button[type="submit"]`

Successful Netlify submission redirects to:

```text
https://www.montaireicesculptures.com/thank-you/
```

The thank-you page fires GA4 event `generate_lead`; verify with GA4 realtime by dimensions `eventName` and metric `eventCount`.
