# 01: GPU quota

Status: **done**. `Running On-Demand G and VT instances` (`L-DB2E81BA`) is 8 vCPUs in us-east-1 in both accounts, approved before Thursday.

Erik: the GPU box runs in the member account by default; the management account is the fallback host ([GPU box](04-gpu-box.md)).

Verify, once per account:

    aws service-quotas get-service-quota --service-code ec2 --quota-code L-DB2E81BA --region us-east-1 --profile cohack --query Quota.Value
    aws service-quotas get-service-quota --service-code ec2 --quota-code L-DB2E81BA --region us-east-1 --profile personal-admin --query Quota.Value

Expected: `8.0` twice. A g6e.xlarge uses 4.
