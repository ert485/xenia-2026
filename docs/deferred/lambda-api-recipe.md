# Lambda API recipe

Reader: for kit maintainers. Cut tier: documented, not built.

## What it was

A second deploy recipe, `infra/recipes/lambda-api/`: an API Gateway HTTP API in front of a Lambda function
built from the team's container image (arm64, from ECR), with a deploy workflow on push to `main` and a
per-PR preview as a Lambda alias plus an API stage at its own hostname.

## Why it was cut

Two build days could prove one deploy path end to end, not two (D21), and the Docker box already runs any API
the team writes, Postgres included (D10). Lambda previews would also need per-PR infrastructure changes:
Terraform plan and apply never run in public CI, and the `preview` role may only run the preview document on
the box (D31), so a preview workflow could not create stages or aliases without a much broader role.

## What exists instead

The `docker-box` recipe (Tasks 6 and 9): `deploy-docker-box.yml` deploys `main` to
`https://app.26.cohack.tetl.ca`, and `preview-up.yml` gives every PR `https://pr-<n>.box.26.cohack.tetl.ca`.
A team that wants serverless can bring its own host (the onboarding page lists no-penalty options).

## How to revive

- Create `infra/recipes/lambda-api/{main.tf,variables.tf,outputs.tf}`: `aws_lambda_function` with
  `package_type = "Image"` and `architectures = ["arm64"]`, `aws_apigatewayv2_api` (HTTP), an integration and
  a `$default` route, a stage, a custom domain `api.26.cohack.tetl.ca` with an ACM certificate in
  ca-central-1, and the execution role.
- Create `infra/examples/hello-lambda/` mirroring `infra/examples/hello-docker-box/`.
- Create `templates/workflows/deploy-lambda.yml` mirroring `deploy-docker-box.yml`: OIDC deploy role, build
  and push the image, then `aws lambda update-function-code --image-uri` and a smoke `curl`. Add the file to
  `allowed-repos.auto.tfvars.json` so the deploy role trusts it.
- Previews: an alias `pr-<n>` per PR and a stage mapping, created by a new SSM-free path. This needs a new
  role with `lambda:UpdateFunctionCode`, `lambda:CreateAlias`, and API Gateway stage rights scoped to the
  function, trusted from any branch: review it against D31 before building it.
- No `shutdown.d/` entry is needed for the function (idle Lambda costs nothing); the custom domain and any
  provisioned concurrency would need one.

Effort: 4 to 6 hours for the recipe, example, and deploy workflow; another 4 to 6 hours for previews,
including the role review.
