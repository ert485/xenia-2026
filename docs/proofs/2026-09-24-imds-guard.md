# Proof: containers off the gateway network can't reach instance metadata

Date: 2026-09-25 01:04 UTC (Thursday evening CST). Plan Task 6, step 15; spec D36 and plan deviation 1.

The Docker box runs IMDSv2 with hop limit 2 (so Caddy and LiteLLM, on the `gateway` network, can use
the instance role), plus a `DOCKER-USER` rule that drops traffic to 169.254.169.254 from every bridge
except `gw0`. The rule is installed before Docker starts on every boot, and re-asserted after any
Docker restart.

## Commands

Run on the box over SSM Run Command (`AWS-RunShellScript`), as root:

```bash
docker run --rm --network edge curlimages/curl:8.10.1 -s -m 3 -X PUT \
  http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' >/dev/null
echo "edge exit $?"
t=$(docker run --rm --network gateway curlimages/curl:8.10.1 -s -m 3 -X PUT \
  http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')
echo "gateway token length ${#t}"
```

## Result

```
edge exit 28
gateway token length 56
```

From `edge` (where the app and every preview run), the request times out (curl exit 28). From
`gateway`, a token comes back (not shown). The box's status document reported `networks: edge
gateway` and `imds guard: on` just before. Task 13 repeats the check from inside a real preview
container.
