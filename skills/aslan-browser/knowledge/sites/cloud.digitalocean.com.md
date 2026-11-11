# DigitalOcean dashboard

- An authenticated dashboard tab can read droplet state through `fetch('/api/v1/droplets/<id>', {credentials:'include', headers:{Accept:'application/json'}})`. The JSON has `droplet.status`. Do not export cookies or dashboard tokens.
- A successful guest `shutdown -h now` can leave dashboard status `active` briefly. Poll until the dashboard reports `off`; the shell command's exit code alone is not proof of power-off.
- Browser-console access does not imply SSH is unavailable. Compare local public-key fingerprints against existing guest `authorized_keys` before proposing new keys. Verify the guest SSH host fingerprint through the console, then pin it for CLI transfer.
- For large source recovery, prefer existing SSH with rsync and file-hash verification. A terminal screenshot is not a backup or an integrity check.
- Keep recovery directories private. Original source documentation and Git history may embed credentials even when standalone environment files are excluded. Never repeat credential values in browser output, reports or task records.
