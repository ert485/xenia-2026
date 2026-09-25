# Per-PR static-site previews

Reader: for kit maintainers. Cut tier: documented, not built.

## What it was

A preview for every PR of a static frontend served from the `static-site` recipe: the PR's build uploaded
under an S3 prefix `pr-<n>/`, served at `pr-<n>.web.26.cohack.tetl.ca` through the same CloudFront
distribution, and deleted when the PR closes.

## Why it was cut

The `static-site` recipe is Must only as the kit site (spec §9), which needs no previews. Per-PR static
previews would need a wildcard certificate in us-east-1, a CloudFront function routing by `Host` header to a
prefix, and a preview role with S3 write access, which widens what a branch workflow can do (D31). Previews on
the Docker box already cover a static frontend.

## What exists instead

A static frontend can live in the team's compose file as a `web` service (for example nginx serving the build
output), so it gets the same `https://pr-<n>.box.26.cohack.tetl.ca` preview as any other app (Task 13). For
`main`, the `static-site` module (Task 19) can serve it at `web.26.cohack.tetl.ca` with its own certificate.

## How to revive

- In `infra/recipes/static-site/`: add an optional wildcard alias `*.web.<zone>`, a us-east-1 ACM certificate
  for it, and a `viewer-request` CloudFront function that maps `pr-<n>.web.<zone>/<path>` to
  `/pr-<n>/<path>` (and appends `index.html` as the existing function does).
- In `infra/platform/oidc.tf`: give the `preview` role `s3:PutObject`, `s3:DeleteObject`, and
  `s3:ListBucket` on the site bucket limited to `pr-*` prefixes, plus `cloudfront:CreateInvalidation` on the
  distribution.
- Create `templates/workflows/static-preview-up.yml` and `static-preview-down.yml` mirroring `preview-up.yml`
  and `preview-down.yml` (same fork guard and comment upsert, `aws s3 sync --delete` to the prefix).
- Idle cost is pennies (S3 storage); the PR can say `Shutdown: none needed because` for that reason.

Effort: 4 to 6 hours, most of it the CloudFront function and certificate validation.
