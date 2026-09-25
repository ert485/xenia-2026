#!/bin/bash
# Re-resolve the allow-listed hostnames and add any new addresses to the allowed-domains set.
# Never flushes or removes anything. init-firewall.sh resolves once at start and CDN-backed hosts
# (the kit site, npm, Discord) rotate addresses; devcontainer.json runs this every 900 seconds.
set -euo pipefail
IFS=$'\n\t'

domains=$(sed -n '/^for domain in/,/; do$/p' /usr/local/bin/init-firewall.sh | grep -oE '"[a-z0-9.-]+"' | tr -d '"')
added=0
for domain in $domains; do
    for ip in $(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}'); do
        [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || continue
        if ! ipset test allowed-domains "$ip" 2>/dev/null; then
            ipset add -exist allowed-domains "$ip"
            added=$((added + 1))
            echo "added $ip for $domain"
        fi
    done
done
echo "refresh-firewall: $added new address(es) at $(date -u +%H:%M:%SZ)"
