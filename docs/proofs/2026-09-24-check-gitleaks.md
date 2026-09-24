# Proof: `check.yml` blocks a planted gateway key

Date: 2026-09-24. Plan Task 2, step 9; spec §17 ("a planted LiteLLM-style key is blocked by push
protection or caught by `gitleaks` in `check.yml`").

## What was done

1. The foundation PR (https://github.com/ert485/xenia-2026/pull/1) ran `check`, which passed:
   https://github.com/ert485/xenia-2026/actions/runs/36073492090
2. A throwaway branch off `build/foundation` added `tests/planted.txt` holding `sk-` followed by 32
   random letters (outside `tests/fixtures/`, so the allow-list doesn't cover it). Push protection
   let it through, as expected: GitHub's push protection matches known provider formats, and a
   LiteLLM virtual key isn't one of them, which is why the kit carries its own gitleaks rule.
3. A draft PR from that branch (https://github.com/ert485/xenia-2026/pull/2) ran `check`, and the
   gitleaks step failed it (`leaks found: 1`, "Leaks detected"):
   https://github.com/ert485/xenia-2026/actions/runs/36073567285
4. PR 2 was closed unmerged and its branch deleted. It was a separate PR rather than a commit on
   the foundation branch because gitleaks scans every commit in a PR, so a revert wouldn't have
   turned the foundation PR green again.

## Result

The custom rule in `.gitleaks.toml` (`sk-[A-Za-z0-9_-]{20,}`) catches a LiteLLM-style key, and
`check` blocks the PR.
