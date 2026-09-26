# The demo table with the recipe's defaults: on-demand, TTL on expires_at, PITR and deletion protection on.
module "demo" {
  source = "../../recipes/dynamodb-table"
  name   = "xenia-demo"
}
