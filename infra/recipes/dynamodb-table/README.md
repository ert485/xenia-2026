# `dynamodb-table` recipe (Should tier)

**Kit status: Should tier. Shipped; not proven end to end unless `docs/proofs/2026-09-25-dynamodb.md` exists in
the kit repo.**

Teammate: an on-demand DynamoDB table with TTL, as a Terraform module. It costs nothing while idle (on-demand
billing, free tier for storage at hackathon sizes), so it needs no `shutdown.d/` entry: a PR adding one carries
`Shutdown: none needed because an idle on-demand table costs nothing`.

## Where it fits, honestly

Apps on the kit's Docker box **cannot use it as-is**: containers on the box have no AWS credentials, because
the box blocks them from the instance metadata endpoint so a preview can't take the box's role. On the box,
use Postgres in your compose file (the default, with hourly backups). Use this recipe when the app runs
somewhere a role can be attached: a Lambda, ECS, or a bring-your-own host with its own credentials.

## Use it

```hcl
module "items" {
  source = "../../recipes/dynamodb-table"   # path from your stack to this folder
  name   = "team-items"
}
```

Defaults: partition key `pk` and sort key `sk` (both strings), TTL on `expires_at` (epoch seconds),
point-in-time recovery on, deletion protection on (decision D15: the realistic weekend risk is an agent
wiping a table). Outputs: `table_name`, `table_arn` (sensitive, it contains the account ID).

## The preview variant

Previews get their own table, suffixed with the PR number, with both protections off so closing the PR can
delete it:

```hcl
module "items_preview" {
  source                 = "../../recipes/dynamodb-table"
  name                   = "team-items"
  name_suffix            = "pr-${var.pr_number}"
  point_in_time_recovery = false
  deletion_protection    = false
}
```

## The IAM statement the app's role needs

Replace `<member-account-id>` with the account (the app's stack can use `data.aws_caller_identity`), and
`team-items` with your table name. The `*` after the name covers the preview tables and the indexes:

```json
{
  "Sid": "AppTable",
  "Effect": "Allow",
  "Action": [
    "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem",
    "dynamodb:Query", "dynamodb:Scan", "dynamodb:BatchGetItem", "dynamodb:BatchWriteItem",
    "dynamodb:ConditionCheckItem"
  ],
  "Resource": [
    "arn:aws:dynamodb:ca-central-1:<member-account-id>:table/team-items*",
    "arn:aws:dynamodb:ca-central-1:<member-account-id>:table/team-items*/index/*"
  ]
}
```

No `dynamodb:DeleteTable` for the app: dropping a table is a Terraform change, reviewed like any other.

## Removing a protected table

Deletion protection is on, so `terraform destroy` fails until you turn it off: set
`deletion_protection = false`, apply, then destroy. That two-step is the point.

## Prove it (kit maintainers)

    scripts/tf.sh examples/dynamodb-demo init
    scripts/tf.sh examples/dynamodb-demo apply
    aws dynamodb describe-table --table-name xenia-demo --profile cohack --region ca-central-1 \
      --query 'Table.[TableStatus,BillingModeSummary.BillingMode,DeletionProtectionEnabled]'
    aws dynamodb describe-continuous-backups --table-name xenia-demo --profile cohack --region ca-central-1 \
      --query 'ContinuousBackupsDescription.PointInTimeRecoveryDescription.PointInTimeRecoveryStatus'
    aws dynamodb describe-time-to-live --table-name xenia-demo --profile cohack --region ca-central-1

Expected: `ACTIVE`, `PAY_PER_REQUEST`, `true`; `ENABLED`; TTL `ENABLED` on `expires_at`.