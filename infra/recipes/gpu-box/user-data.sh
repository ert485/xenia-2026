#!/usr/bin/env bash
# GPU box first boot (AWS Deep Learning Base OSS Nvidia Driver AMI, Ubuntu 24.04, x86_64).
# Rendered by templatefile() in main.tf. The two lines around the assume-role block are Terraform
# template directives (percent-brace if/endif with trim markers), not shell; shellcheck reads them
# as broken shell syntax, so those two lines are disabled individually rather than excluding the
# whole file from lint.
# shellcheck disable=SC2154
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

hostnamectl set-hostname xenia-gpu-box
apt-get update -q
apt-get install -y -q jq git curl unzip python3-yaml
# Ubuntu 24.04 has no awscli package; the DLAMI usually ships AWS CLI v2, install it if not.
if ! command -v aws >/dev/null 2>&1; then
  curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscli.zip
  unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install
fi
docker compose version >/dev/null 2>&1 || apt-get install -y -q docker-compose-plugin

mkdir -p /data/hf /etc/xenia/tls /run/xenia
chmod 0700 /etc/xenia /run/xenia

if [ ! -d /srv/kit/.git ]; then
  git clone --depth 1 --branch "${kit_ref}" "https://github.com/${kit_repo}.git" /srv/kit
fi
recipe=/srv/kit/infra/recipes/gpu-box
chmod +x "$recipe/watchdog.sh"

# Secrets from the member account's SSM (ca-central-1). No command tracing while they are handled.
set +x
# shellcheck disable=SC1083,SC2288
%{ if reader_role_arn != "" ~}
creds="$(aws sts assume-role --role-arn "${reader_role_arn}" --role-session-name xenia-gpu-boot --query Credentials --output json)"
AWS_ACCESS_KEY_ID="$(jq -r .AccessKeyId <<< "$creds")"; export AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY="$(jq -r .SecretAccessKey <<< "$creds")"; export AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN="$(jq -r .SessionToken <<< "$creds")"; export AWS_SESSION_TOKEN
# shellcheck disable=SC1083,SC2288
%{ endif ~}
get() { aws ssm get-parameter --region ca-central-1 --name "/xenia/gpu/$1" --with-decryption --query Parameter.Value --output text; }
umask 077
get vllm-cert > /etc/xenia/tls/cert.pem
get vllm-key > /etc/xenia/tls/key.pem
chmod 0644 /etc/xenia/tls/cert.pem
chmod 0600 /etc/xenia/tls/key.pem
{
  printf 'VLLM_API_KEY=%s\n' "$(get vllm-token)"
  printf 'MODEL_REPO=%s\n' "${model_repo}"
  printf 'TOOL_PARSER=%s\n' "${tool_parser}"
  printf 'MAX_NUM_SEQS=%s\n' "${max_num_seqs}"
  printf 'EXTRA_ARGS=%s\n' "${extra_args}"
  if hf="$(get hf-token 2>/dev/null)"; then printf 'HF_TOKEN=%s\n' "$hf"; fi
} > /etc/xenia/vllm.env
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN creds
set -x

cd "$recipe"
docker compose up -d

cat > /etc/systemd/system/xenia-vllm-watchdog.service <<'EOF'
[Unit]
Description=xenia: restart vLLM after three failed health probes
After=docker.service

[Service]
Type=oneshot
ExecStart=/srv/kit/infra/recipes/gpu-box/watchdog.sh
EOF
cat > /etc/systemd/system/xenia-vllm-watchdog.timer <<'EOF'
[Unit]
Description=xenia: vLLM watchdog every minute

[Timer]
OnBootSec=15min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now xenia-vllm-watchdog.timer

# GPU memory metrics (spec section 10). Best effort: never fail the boot over monitoring.
if [ ! -x /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl ]; then
  if curl -fsSL -o /tmp/cwagent.deb https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb; then
    dpkg -i /tmp/cwagent.deb || echo "WARNING: CloudWatch agent install failed; GPU memory metrics unavailable" >&2
  else
    echo "WARNING: CloudWatch agent download failed; GPU memory metrics unavailable" >&2
  fi
fi
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
  -c "file:$recipe/cloudwatch-agent.json" || true
