# 02: DNS delegation at GoDaddy

Status: **done** Wednesday 2026-09-23.

Erik: the Route 53 zone `26.cohack.tetl.ca` lives in the member account. GoDaddy holds four NS records for host `26.cohack` pointing at the zone's name servers; no other `tetl.ca` record changed.

Verify:

    dig +short NS 26.cohack.tetl.ca

Expected: four `awsdns` name servers, matching `scripts/tf.sh platform output name_servers`.
