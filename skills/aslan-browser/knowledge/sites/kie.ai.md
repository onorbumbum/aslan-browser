# Kie.ai

- Open `https://kie.ai/logs` directly to inspect authenticated task history. The marketing homepage can remain unchanged when its links are clicked; that does not establish that the account is signed out.
- Logs has an All Status filter, model filter, task ID filter and paginated grid. Read model, timestamp, status and task ID without copying other clients' prompts. Never click Retry Callback or Batch Callback during read-only reconciliation.
- Absence of a failed createTask call from Logs does not prove that the request had no external effects. A rejected submission may never become a task row.
