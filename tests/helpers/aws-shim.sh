#!/usr/bin/env bash
# Fake aws CLI for bats. Records every call in $AWS_CALLS; answers from $FAKE_STATE.
printf '%s\n' "$*" >> "${AWS_CALLS:-/dev/null}"
case "$*" in
  *"sts get-caller-identity"*)      printf '%s\n' "${FAKE_ACCOUNT:-000000000}" ;;
  *"s3api head-bucket"*)            [[ -f "$FAKE_STATE/bucket" ]] ;;
  *"s3api create-bucket"*)          touch "$FAKE_STATE/bucket" ;;
  *"dynamodb describe-table"*)      [[ -f "$FAKE_STATE/table" ]] ;;
  *"dynamodb create-table"*)        touch "$FAKE_STATE/table" ;;
  *"dynamodb wait"*)                exit 0 ;;
  *) exit 0 ;;
esac
