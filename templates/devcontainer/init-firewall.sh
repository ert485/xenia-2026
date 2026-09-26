#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

# xenia: fail-CLOSED ordering (controller ruling, fix round 1). The default-deny policies go up
# FIRST -- loopback, established/related, DNS to the container's resolver, and the devcontainer's
# own host network are the only things allowed before a single allow-list host is resolved. A
# host that does not resolve yet (a gateway not deployed yet, say) gets a WARNING and is skipped,
# never an abort that leaves the firewall half-applied. The trap re-asserts the DROP policies on
# any unexpected error or exit, so a mid-script failure cannot leave egress open.
trap 'iptables -P INPUT DROP 2>/dev/null || true; iptables -P OUTPUT DROP 2>/dev/null || true; iptables -P FORWARD DROP 2>/dev/null || true' ERR EXIT

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# 2. Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# Baseline, allowed before anything else: outbound DNS, inbound DNS responses, outbound SSH,
# inbound SSH responses, loopback, and established/related in both directions.
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Host network (the devcontainer's own gateway/subnet): local routing info only, no network call.
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi
HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# The allowed-domains ipset, and the OUTPUT rule that consults it -- created and wired in before
# it holds anything. Allow-list hosts populate it below, after default-deny is already in force.
ipset create allowed-domains hash:net
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Default-deny NOW, before any allow-list host is resolved. From this line on, only loopback,
# established/related, DNS, the host network, and whatever lands in allowed-domains can get out.
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Explicit REJECT for immediate feedback (icmp) instead of a silent drop on anything the rules
# above didn't match; the DROP policy is what actually enforces the posture either way.
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

allow_host() {
    # Resolve one hostname and add its A records to allowed-domains. A hostname that does not
    # resolve yet gets a WARNING and is skipped -- never an abort with the firewall half-applied
    # (a not-yet-deployed gateway host, for example, must not force egress open).
    domain="$1"
    echo "Resolving $domain..."
    ips="$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')"
    if [ -z "$ips" ]; then
        echo "WARNING: $domain did not resolve yet; skipping (refresh-firewall.sh adds it once it does)"
        return 0
    fi
    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        echo "Adding $ip for $domain"
        ipset add -exist allowed-domains "$ip"
    done <<< "$ips"
}

# GitHub's own address first: DNS is already allowed but nothing else is, and api.github.com must
# be reachable to fetch the full web/api/git ranges below.
allow_host "api.github.com"

echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi

if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi

echo "Processing GitHub IPs..."
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    echo "Adding GitHub range $cidr"
    ipset add -exist allowed-domains "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

# Resolve and add other allowed domains
# xenia: the kit's list (spec section 11). refresh-firewall.sh reads this loop header, so keep one
# quoted hostname per line. A host that does not resolve yet is a WARNING (see allow_host), not a
# failure: the gateway, for instance, may not be deployed yet.
for domain in \
    "registry.npmjs.org" \
    "api.anthropic.com" \
    "pypi.org" \
    "files.pythonhosted.org" \
    "llm.26.cohack.tetl.ca" \
    "app.26.cohack.tetl.ca" \
    "26.cohack.tetl.ca" \
    "discord.com" \
    "discordapp.com" \
    "ghcr.io" \
    "objects.githubusercontent.com" \
    "codeload.github.com" \
    "release-assets.githubusercontent.com" \
    "awscli.amazonaws.com" \
    "sts.ca-central-1.amazonaws.com" \
    "ssm.ca-central-1.amazonaws.com" \
    "public.ecr.aws" \
    "registry.terraform.io" \
    "releases.hashicorp.com" \
    "marketplace.visualstudio.com" \
    "vscode.blob.core.windows.net" \
    "update.code.visualstudio.com"; do
    allow_host "$domain"
done

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

# Verify GitHub API access
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi
