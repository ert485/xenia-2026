# Proof: `agent-verify.sh` v0 (Task 32)

Date: 2026-09-25. Plan: `docs/superpowers/plans/2026-09-25-container-first-workflow.md`, Task 32
(verifier v0; components 1 and 2). Ledger task text: `.superpowers/sdd/2026-09-24-cohack-prep-kit/task-32-brief.md`.

## What was done

- `plugin/scripts/agent-verify.sh` (the verifier) and `scripts/agent-verify.sh` (thin wrapper).
- `tests/agent-verify.bats`: a fixture git repository per test, replaying the three Thursday-night
  battle-test incidents plus the rest of the interface.
- `templates/devcontainer/Dockerfile` and `.devcontainer/Dockerfile` (kept byte-identical): `bats`
  and `shellcheck` added to the apt list; `actionlint` v1.7.11 downloaded for the image's
  architecture; `zizmor` added to the pipx line; a venv at `/opt/xenia/venv` with
  `mkdocs-material`, `segno`, and `pyyaml`, put first on `PATH`.
- `templates/devcontainer/init-firewall.sh` and `.devcontainer/init-firewall.sh` (same rule):
  `registry.terraform.io` and `releases.hashicorp.com` added to the allow-list (`make validate`
  downloads providers).
- `.gitignore`: `.agent/` and `.agent-requests/` added under the local-only section.

## TDD evidence

RED (`bats tests/agent-verify.bats`, with `plugin/scripts/agent-verify.sh` moved aside): all 16
tests failed (14 from the initial implementation, plus two added in fix round 1 for findings 1 and
3 below):

```
1..16
not ok 1 pass: a clean branch with a script change and a test change
not ok 2 replay Task 15: a fake proof is blocked until a result file backs it
not ok 3 replay Task 20: zero-byte and whitespace-only files block, .gitkeep is spared
not ok 4 replay Task 29: a hidden make-check failure blocks and an unjustified fallback warns
not ok 5 an ok-to-hide justification suppresses the failure-hiding warning
not ok 6 root-files: stray untracked reports block; REPORT.md, an allow-listed name, and a new dir are spared
not ok 7 make-check: a check target removed since the base commit blocks
not ok 8 scripts-without-tests warns alone, not when a test also changed
not ok 9 uncommitted-changes warns, dirty is true, and an uncommitted 0-byte file still blocks
not ok 10 --skip make-check never runs make: no log, and the check target's own side effect never happens
not ok 11 uncommitted-changes on a rename warns with the new path, not the old -> new form
not ok 12 --skip drops a check and --warn demotes one to pass
not ok 13 REPORT.md is never read as evidence, and the script names it exactly once
not ok 14 a bogus --base ref and running outside a git worktree both error
not ok 15 an unknown check name to --skip exits 2
not ok 16 --help lists all seven check names
```

GREEN (same command, script restored): all 16 pass, including the three replayed incidents and
the two fix-round tests:

```
1..16
ok 1 pass: a clean branch with a script change and a test change
ok 2 replay Task 15: a fake proof is blocked until a result file backs it
ok 3 replay Task 20: zero-byte and whitespace-only files block, .gitkeep is spared
ok 4 replay Task 29: a hidden make-check failure blocks and an unjustified fallback warns
ok 5 an ok-to-hide justification suppresses the failure-hiding warning
ok 6 root-files: stray untracked reports block; REPORT.md, an allow-listed name, and a new dir are spared
ok 7 make-check: a check target removed since the base commit blocks
ok 8 scripts-without-tests warns alone, not when a test also changed
ok 9 uncommitted-changes warns, dirty is true, and an uncommitted 0-byte file still blocks
ok 10 --skip make-check never runs make: no log, and the check target's own side effect never happens
ok 11 uncommitted-changes on a rename warns with the new path, not the old -> new form
ok 12 --skip drops a check and --warn demotes one to pass
ok 13 REPORT.md is never read as evidence, and the script names it exactly once
ok 14 a bogus --base ref and running outside a git worktree both error
ok 15 an unknown check name to --skip exits 2
ok 16 --help lists all seven check names
```

`shellcheck -x plugin/scripts/agent-verify.sh scripts/agent-verify.sh` is clean (exit 0).

## Step 5: the verifier judging this very worktree

With `docs/proofs/2026-09-25-agent-verify.md` written as a stub (before this final version) and
nothing else committed, `scripts/agent-verify.sh` (no flags) reported exactly one reason. The
absolute local path in the `-> ...STATUS.json` line below has been shortened to `<worktree>`;
every other byte is the real recorded output:

```
agent-verify: blocked (1 reasons, 9 warnings) -> <worktree>/.agent/STATUS.json
  blocked proofs-unbacked: docs/proofs/2026-09-25-agent-verify.md: no .agent-requests/*.result.md references this path
  warning uncommitted-changes: .devcontainer/Dockerfile: uncommitted or untracked change
  warning uncommitted-changes: .devcontainer/init-firewall.sh: uncommitted or untracked change
  warning uncommitted-changes: .gitignore: uncommitted or untracked change
  warning uncommitted-changes: templates/devcontainer/Dockerfile: uncommitted or untracked change
  warning uncommitted-changes: templates/devcontainer/init-firewall.sh: uncommitted or untracked change
  warning uncommitted-changes: docs/proofs/2026-09-25-agent-verify.md: uncommitted or untracked change
  warning uncommitted-changes: plugin/scripts/: uncommitted or untracked change
  warning uncommitted-changes: scripts/agent-verify.sh: uncommitted or untracked change
  warning uncommitted-changes: tests/agent-verify.bats: uncommitted or untracked change
exit=1
```

`scripts/agent-verify.sh --warn proofs-unbacked` turned that same reason into a warning and passed:

```
agent-verify: pass (0 reasons, 10 warnings) -> <worktree>/.agent/STATUS.json
  warning proofs-unbacked: docs/proofs/2026-09-25-agent-verify.md: no .agent-requests/*.result.md references this path
  warning uncommitted-changes: .devcontainer/Dockerfile: uncommitted or untracked change
  warning uncommitted-changes: .devcontainer/init-firewall.sh: uncommitted or untracked change
  warning uncommitted-changes: .gitignore: uncommitted or untracked change
  warning uncommitted-changes: templates/devcontainer/Dockerfile: uncommitted or untracked change
  warning uncommitted-changes: templates/devcontainer/init-firewall.sh: uncommitted or untracked change
  warning uncommitted-changes: docs/proofs/2026-09-25-agent-verify.md: uncommitted or untracked change
  warning uncommitted-changes: plugin/scripts/: uncommitted or untracked change
  warning uncommitted-changes: scripts/agent-verify.sh: uncommitted or untracked change
  warning uncommitted-changes: tests/agent-verify.bats: uncommitted or untracked change
exit=0
```

No other reason and no unexpected warning showed up (only `uncommitted-changes`, expected since
nothing was committed yet).

## Step 6: the dev container image

`BUILDX_BUILDER=desktop-linux docker build -f templates/devcontainer/Dockerfile -t
xenia-devcontainer:task32 .` succeeded (image `xenia-devcontainer:task32`, built for `linux/arm64`
on this Mac). Building it surfaced two real bugs, both fixed in this task before the proof below:

1. `/etc/profile` resets `PATH` for a login shell, which is what `bash -lc` (the brief's own
   Step 6 command, and what a devcontainer terminal opens) uses. The Dockerfile's plain `ENV PATH`
   was silently dropped, so `mkdocs` and `segno` were missing under `bash -lc` even though they
   worked under a plain `bash -c`. Fixed with a `/etc/profile.d/xenia-venv-path.sh` script that
   restores the venv ahead of the rest of `PATH` for every shell, login or not.
2. The apt-packaged `bats` in the image is 1.8.2 (Debian's), much older than the Mac's Homebrew
   1.14.0. Its preprocessor scans a `.bats` file's raw text for the token that starts a test,
   without understanding bash syntax, so a fixture written into a heredoc inside
   `tests/agent-verify.bats` (a fake `tests/hello.bats` for another repo, used only as a "some
   test file changed" marker) was miscounted as an extra test of the outer file, producing a false
   `bats: unknown test name` failure only on the older bats. Fixed by building that one token at
   runtime in the fixture instead of writing it as a contiguous literal, so the outer file's raw
   text never contains it outside a real `@test` line.

After both fixes, every tool version printed under the exact Step 6 command
(`docker run --rm ... bash -lc '...'`):

```
Bats 1.8.2
ShellCheck - shell script analysis tool
version: 0.9.0
1.7.11
installed by downloading from release page
built with go1.25.7 compiler for linux/arm64
zizmor 1.30.1
mkdocs, version 1.6.1 from /opt/xenia/venv/lib/python3.11/site-packages/mkdocs (Python 3.11)
1.6.6
```

(the last line is `segno.__version__`, printed by `python3 -c "import segno, yaml; print(segno.__version__)"`,
proving both `segno` and `yaml` import with plain `python3`, no `.venv` or `make tools` needed).

`bats tests/agent-verify.bats` inside the container, after the bats-1.8.2 fix, matches the Mac
exactly: `1..14`, all 14 `ok`, no bats warning. (Fix round 1 added two more tests after this
container run; they are proven on the Mac only — see TDD evidence above — since fix round 1
was explicitly told not to touch Docker while the daemon was hung and this Mac had about 2 GiB
free. Both fixed findings from that round are covered by those two tests either way.)

**Concern, not resolved in this task's control:** the full `make check` inside the container could
not be proven end to end. `make validate` downloads a fresh `hashicorp/aws` provider per stack
(four stacks with a `versions.tf`), and this Mac's root volume ran out of free space partway
through (`no space left on device` while writing the provider binary for `infra/org`), the same
failure `make check` hit natively on the Mac before `.terraform-validate/` caches from a prior run
were cleared. Three other devcontainer sessions (`battle-15`, `battle-20`, `battle-29`) were still
running for 7 to 13 hours on this same Mac during this proof, competing for the same disk; deleting
their images or containers to free space was out of scope for this task and risked their work, so
this was reported rather than forced through. What is proven instead: every stack validates cleanly
on its own (`terraform init -backend=false && terraform validate`, run and cleaned up one stack at
a time on the Mac, natively, for `org`, `platform`, `recipes/docker-box`, and `recipes/gpu-box`),
and the full, unmodified `make check` passes end to end natively on the Mac once disk headroom
exists (see below) — so the container's tool additions and firewall/gitignore changes are not the
blocker; the shared host's free disk is.

## Mac `make check` (native), full run

After clearing stale `.terraform-validate/` caches from an earlier interrupted run to give
`terraform init` room to download providers:

```
...
ok 96 reachable backend: prints the real api_base and logs reachable
ok 97 unreachable backend: prints the placeholder and logs why
ok 98 already the placeholder: never probes, just prints it back
 INFO zizmor: 🌈 zizmor v1.30.1
 WARN audit: zizmor: zizmor is running in offline mode by default; some audits and auto-fixes will not be available.
 INFO audit: zizmor: 🌈 completed .github/workflows/check.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/deploy-docker-box.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/devcontainer-image.yml
 INFO audit: zizmor: 🌈 completed templates/workflows/check.yml
 INFO audit: zizmor: 🌈 completed templates/workflows/deploy-docker-box.yml
 INFO audit: zizmor: 🌈 completed templates/workflows/devcontainer-image.yml
No findings to report. Good job! (12 suppressed)
make check: OK
```

97 tests ran and passed (`1..97`, 0 `not ok`), including the 14 new tests from the initial
implementation, plus the kit's existing suite (deploy, box, gateway-key, GPU capacity/lifecycle,
leak-check, tf.sh, and the rest), unchanged by this task's Dockerfile/gitignore/firewall edits.
Fix round 1's two additional tests are not reflected in this tail (a fresh full `make check` was
explicitly out of scope for that round, since its own `terraform init` writes providers to a Mac
disk that had about 2 GiB free at the time); they are proven directly via `bats
tests/agent-verify.bats`, shown 16/16 in the TDD evidence above.

## Result

`plugin/scripts/agent-verify.sh` turns each of the three battle-test incidents into a permanent,
deterministic `blocked` verdict (`proofs-unbacked`, `empty-files`, `make-check` plus the
`failure-hiding` warning), never reads `REPORT.md`, and writes `.agent/STATUS.json` for a Stop hook
or CI job to consume in a later task. The dev container image carries the same test tools the Mac
uses, with two portability bugs found and fixed along the way (see Step 6 above).
