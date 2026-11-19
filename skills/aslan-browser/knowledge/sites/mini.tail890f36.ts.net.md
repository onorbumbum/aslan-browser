# Ops dashboard (mini.tail890f36.ts.net)

Onur's Ops dashboard on the Mac mini, over the tailnet: `https://mini.tail890f36.ts.net/#/...` (same hash routes as `http://127.0.0.1:8765` on the Mini). Writes that only Onur may make (commitment Run at / Autonomy / Model / Thinking, approvals) are accepted only from this page; its POST endpoints refuse other callers ("Writes come only from the dashboard page"). Drive the page only on Onur's explicit instruction.

- **Never use `--wait idle`**: the page holds an open `/events` stream, so idle never arrives and `aslan nav` hangs past the tool timeout. Use `--wait load`, or change routes with `aslan eval 'location.hash="#/commitments"; return 1'` and `sleep 2`.
- Commitments page `#/commitments`: one card per commitment, each with an `Edit…` button; refs repeat ("Automate it, or end it"), so find the card by its Deliverable text in `eval` and click its `Edit…`.
- The Edit form (a `<form>` containing the Deliverable heading) has `textarea[name=done_when]`, `input[name=auto]` (checkbox "Start an agent on each new task" = Run at set), `input[name=days]` (days into the period), `input[name=time]` (HH:mm, default 09:00), `select[name=autonomy]` (`prepare` | `pre-approved`), `input[name=model]`, `select[name=thinking]`, `input[name=end]`, then `Save`. Run at is stored as `+<days> <time>`.
- After Save the card reads e.g. "Agent runs on the first day of each period at 09:00 · prepares, you approve". Verify with `toolshed ops list --tab Commitments` on the Mini.
