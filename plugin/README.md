# xenia-kit plugin

The Co.Hack 2026 kit's Claude Code plugin. It is seeded into the dev container image at user scope
(`CLAUDE_CODE_PLUGIN_SEED_DIR=/opt/xenia/plugins`), so it is active in every repo opened there, and
it is vendored into each team repo at `plugin/`.

## What it does

- **SessionStart hook**: on start, resume, clear, and compact, injects the team's core rules. It reads
  `PRINCIPLES.md` from the open repo only if that repo is listed in `allowed-repos.txt`, capped at 4 KB,
  and otherwise injects the bundled copy with a note. No network access.
- **Skills**: `/pain` (log friction as an issue), `/rule-feedback` (record a knowing exception),
  `/notify` (post to the team's Discord), `/doctor` (check the setup), `/preview` (this PR's preview),
  `/shutdown-entry` (scaffold a `shutdown.d/` entry), `/demo-checklist`.
- **Stop hook**: on every stop, runs `plugin/scripts/agent-verify.sh` against the worktree and blocks
  the stop until it passes, up to three attempts per session; see "Stop hook" below.
- **Deny hooks**: PreToolUse hooks that deny a short list of ruinous commands before they run; see
  "Deny hooks" below.

## Naming who is who (P-who)

Skills address the agent and start with "Agent:"; they call the human "the teammate". The CI reviewer
calls itself "bot". Keep that when adding a skill.

## Other teams

You are welcome to use it. Pin it by commit rather than following `main`: copy `plugin/` from a
specific commit of `ert485/xenia-2026`, and add your repo to `allowed-repos.txt` in your copy.

## Updating

Seeded plugins never auto-update. After a plugin change: `claude plugin update xenia-kit` in the
container, or rebuild the image (the `devcontainer-image` workflow publishes one on every push to
`main` that touches `plugin/`). Rule text changes need neither: the hook reads `PRINCIPLES.md` from
the open repo at each session start.

If the seed directory is not picked up (`claude plugin list` shows no `xenia-kit`), add
`claude plugin install /opt/xenia/plugins/xenia-kit` to `.devcontainer/postCreate.sh`; if that
command refuses a local path, add `alias claude='claude --plugin-dir /opt/xenia/plugins/xenia-kit'`
to the shell block `postCreate.sh` writes instead.

## Stop hook

`plugin/hooks/stop-verify.sh` runs on every `Stop` event. It runs
`plugin/scripts/agent-verify.sh --worktree <cwd>` (Task 32's verifier) and, when it comes back
`blocked` or `error`, blocks the stop and hands the agent the reasons, up to three attempts per
session (counted in `.agent/stop-attempts-<session_id>`, gitignored). On the fourth stop it lets the
session end but leaves a `systemMessage` saying so, plus the reasons in `.agent/STATUS.json` — that
file is what to read to see why it fired. Set `XENIA_VERIFY_ARGS` (for example
`--skip make-check`) in the environment to tune which checks run, without editing the plugin. It
never blocks on its own failure: if the verifier itself can't run, the hook fails open with a
`systemMessage` and CI's copy of the same checks (Task 14) is the backstop.

## Deny hooks

`plugin/hooks/deny-ruinous.sh` runs on every `Bash`, `Write`, `Edit`, `MultiEdit`, and `NotebookEdit`
call and denies a short, fixed list of ruinous commands: a force push, deleting the workspace root
or running `git clean -fx`, editing the egress firewall scripts or sudoers, and writing under
`docs/proofs/` or `.agent/` (the verifier's own verdict). A `Bash` call is judged by tokenizing it
the way a shell would (via `python3`'s `shlex`) and checking each simple command's real subcommand
and arguments — never by matching a raw substring, so a commit message or an `echo` that only
*mentions* `git push --force` is never treated as running it. If `python3` is missing, or the
command's quoting can't be safely parsed, the call is denied rather than guessed at. Everything else
is allowed; this is a guardrail against the obvious, not a sandbox — the firewall and the absence of
deploy credentials in the container are the real boundary. A denied call's reason names the rule and
says what to do instead (usually: file a `.agent-requests/` request, or ask the human); to see why a
call was denied, read that reason in the transcript.
