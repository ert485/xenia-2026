# 00b: MFA and repo scanning

Status: **done** 2026-09-24 (the optional upgrades are not required).

Erik: the management account holds the card, so its root user and Erik's Identity Center user both have MFA (authenticator apps, checked 2026-09-24).

1. Optional: add a passkey or security key as a second MFA device on the root user (**Security credentials, Assign MFA device, Passkey or security key**).
2. Optional: allow security keys in Identity Center (**Settings, Authentication**) and register one on Erik's user.
3. Secret scanning and push protection are on for the kit repo. Non-provider patterns aren't offered on this plan; `gitleaks` in `check.yml` and the dev container's pre-commit hook cover gateway keys.
4. Optional: set this repo's commit email to the GitHub noreply address shown under GitHub **Settings, Emails** (`git config user.email` with that value, in this repo only).

Verify: `gh api repos/ert485/xenia-2026 --jq .security_and_analysis` shows `secret_scanning` and `secret_scanning_push_protection` enabled.
