#!/usr/bin/env bash
# Fake aws CLI for bats. Records every call in $AWS_CALLS; answers from $FAKE_STATE.
printf '%s\n' "$*" >> "${AWS_CALLS:-/dev/null}"
case "$*" in
  *"sts get-caller-identity"*)      printf '%s\n' "${FAKE_ACCOUNT:-000000000}" ;;
  *"configure export-credentials"*)
    if [[ -n "${FAKE_EXPORT_CREDS_FAIL:-}" ]]; then
      exit 1
    fi
    printf 'export AWS_ACCESS_KEY_ID="%s"\nexport AWS_SECRET_ACCESS_KEY=FAKESECRET\nexport AWS_SESSION_TOKEN=FAKETOKEN\n' "FAKEKEY-$*" ;;
  *"s3api head-bucket"*)            [[ -f "$FAKE_STATE/bucket" ]] ;;
  *"s3api create-bucket"*)          touch "$FAKE_STATE/bucket" ;;
  *"dynamodb describe-table"*)      [[ -f "$FAKE_STATE/table" ]] ;;
  *"dynamodb create-table"*)        touch "$FAKE_STATE/table" ;;
  *"dynamodb wait"*)                exit 0 ;;
  *"organizations list-policies"*)
    if [[ -f "$FAKE_STATE/scp" ]]; then printf '{"Policies":[{"Id":"p-lockdown1","Name":"xenia-lockdown"}]}\n'
    else printf '{"Policies":[]}\n'; fi ;;
  *"organizations list-targets-for-policy"*)
    if [[ -f "$FAKE_STATE/scp-attached" ]]; then printf '{"Targets":[{"TargetId":"%s","Type":"ACCOUNT"}]}\n' "${FAKE_MEMBER:-}"
    else printf '{"Targets":[]}\n'; fi ;;
  *"organizations attach-policy"*)  touch "$FAKE_STATE/scp-attached" ;;
  *"organizations detach-policy"*)  rm -f "$FAKE_STATE/scp-attached" ;;
  *) exit 0 ;;
esac
