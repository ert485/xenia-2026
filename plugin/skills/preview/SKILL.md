---
name: preview
description: Use when the teammate types /preview, or asks where this branch's preview environment is or whether it is up.
---

Agent: show this branch's preview.

1. Run the plugin's script (two levels above this skill's base directory):

   ```bash
   <plugin root>/scripts/preview.sh
   ```

2. Tell the teammate the preview URL, its HTTP status, and the state of the latest `preview-up` run. A `404` saying "no such preview" means the preview isn't running: the run may still be going, or it failed (give its URL).
3. Previews are capped at three on the box; the oldest is removed when a fourth starts, and pushing to that PR brings it back.
