# Proof: OIDC deploy-role trust string

**NOT YET RUN.** This is a template: the controller fills in the run URLs and masked output after
each real dispatch, then removes this marker line.

## What this proves

The `deploy` role (`xenia-deploy-ert485-xenia-2026`) trusts only
`repo:ert485@6201488/xenia-2026@1384206368:ref:refs/heads/main:job_workflow_ref:ert485/xenia-2026/.github/workflows/oidc-probe.yml@refs/heads/main`.

The repo segment is `OWNER@OWNER_ID/REPO@REPO_ID`, not `OWNER/REPO`, because GitHub gives repos
created after 2026-07-15 immutable subject claims
([changelog](https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/)),
and they can't be turned off. An earlier branch run printed this form, which is how the original
`repo:ert485/xenia-2026:...` trust was found to be unassumable. The segment comes from
`gh api repos/ert485/xenia-2026/actions/oidc/customization/sub` (`.sub_claim_prefix`) and is kept in
`infra/platform/oidc-sub-prefixes.auto.tfvars.json`. The `job_workflow_ref` segment still uses
plain names. The owner and repo IDs are public.

Two runs of `.github/workflows/oidc-probe.yml` show that trust holding: a run from a branch is
denied, a run from `main` succeeds.

## Command

`oidc-probe.yml` exists only on `build/foundation` so far, and `gh workflow run` cannot dispatch a
workflow that only exists on a branch (pre-flight ruling 4.1) — that's why the workflow carries a
temporary `push: branches: [build/foundation]` trigger. Run 1 therefore fires automatically on the
next push to `build/foundation`; it must happen **after** Step 6 has set the
`AWS_DEPLOY_ROLE_ARN` repo secret (`role-to-assume` is empty/invalid otherwise). No `gh workflow
run` is needed for it.

Run 2, after the foundation PR has merged to `main` (the workflow file now exists on the default
branch, so `workflow_dispatch` can target it):

```bash
gh workflow run oidc-probe.yml --ref main
```

## Run 1: triggered by a push to `build/foundation`, after Step 6 (expected to fail the assume step)

- Run URL: _not yet run_
- Printed `sub`: expected exactly
  `repo:ert485@6201488/xenia-2026@1384206368:ref:refs/heads/build/foundation:job_workflow_ref:ert485/xenia-2026/.github/workflows/oidc-probe.yml@refs/heads/build/foundation`
- Assume step: expected to fail with `Not authorized to perform sts:AssumeRoleWithWebIdentity`

If the printed `sub` format differs (for example, no `job_workflow_ref` segment, or a different
repo segment), the `values` expression in `data.aws_iam_policy_document.deploy_trust`
(`infra/platform/oidc.tf`) or the repo's entry in `oidc-sub-prefixes.auto.tfvars.json` needs fixing
to match the real format, followed by a re-apply.

## Run 2: from `main` (expected to succeed)

- Run URL: _not yet run_
- Masked `who am I` line: expected
  `arn:aws:sts::<account-id>:assumed-role/xenia-deploy-ert485-xenia-2026/...`

## Cleanup

The `push: branches: [build/foundation]` trigger on `oidc-probe.yml` is temporary and must be
removed before merging to `main` (kept as `workflow_dispatch` only). The whole workflow file is
deleted in Task 9.
