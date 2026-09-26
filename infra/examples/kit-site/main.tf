variable "state_bucket" { type = string }

data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket  = var.state_bucket
    key     = "platform.tfstate"
    region  = "ca-central-1"
    profile = "cohack"
  }
}

# The kit site at the zone apex (spec section 6, D18).
module "site" {
  source          = "../../recipes/static-site"
  domain          = data.terraform_remote_state.platform.outputs.zone_name
  zone_id         = data.terraform_remote_state.platform.outputs.zone_id
  certificate_arn = data.terraform_remote_state.platform.outputs.apex_certificate_arn
  name            = "kit"
}
