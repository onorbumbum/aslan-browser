# Read-only Search Console indexing-alert triage

## Inputs

- Exact property returned by the authorized connector's sites list.
- Notification reason and its actual mail date.
- Project report directory and existing Ops task, when client work.

## Preconditions

Follow current google-search-console/SKILL.md caller authorization. Do not invent an admin header or switch credential stores to bypass it. This connector may use a skill-local OAuth grant distinct from other Google tools. Normal refresh of an existing grant is not a new consent request.

Confirm actual property permission through the API and inspect the authenticated browser account. Use a dedicated ASLAN_SESSION and newly created tab, pin every operation to its observed tab ID. Leave other actors' tabs untouched.

## Steps

1. Open the indexing overview with the exact encoded property ID: https://search.google.com/search-console/index?resource_id=<encoded-property>. Read tree/text and verify property/account.
2. Read actual reason rows from `tr` text. Do not infer an issue from the notification title alone.
3. Click only the observed reason row. Read again until the reason heading and Examples table replace the overview. Do not click Validate fix.
4. Save the displayed Last update, First detected, affected count, exact example URLs and example Last crawled dates. The default table has ten rows; paginate only as needed and state any sampling limit. Hidden overview rows can remain in the DOM, so an all-tr query is not itself the affected-URL list.
5. Use cached URL Inspection API reads on the exact examples and their canonical destination or representative content page. Capture verdict, coverage state, fetch state, lastCrawlTime, declared and Google-selected canonical, referring URLs and sitemap association. Keep the number bounded; no request indexing or live-validation action.
6. Compare current public behavior and intended URL policy with Google's actual examples. Duplicate parameter URLs can be intentionally excluded while the clean canonical is indexed. Internal generated utility paths are not automatically missing content pages. Do not fabricate a redirect or remove a canonical to clear a category.
7. Write the project report and update the same Ops task with actual findings. Close a triage task only when its original investigation criteria are verified; never claim a source repair, indexing submission or complete-site audit from these reads.

## Interpretation

Notification date, category First detected, overview Last update, example Last crawled and API lastCrawlTime are different observations and may differ. Label them individually. A normal exclusion is not automatically a defect. Do not start validation just because no repair is needed.

## Output

A short explanation with exact affected URLs, crawl/canonical facts, intended behavior, any remaining uncertainty and whether further authorized work is needed. Retain machine-readable API evidence and a report screenshot without cookies or credential values. Keep the relevant tabs open for the owner if useful.
