resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "backups" {
  bucket        = "xenia-backups-${random_id.suffix.hex}"
  force_destroy = false
}
resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    id     = "expire-old-dumps"
    status = "Enabled"
    filter {}
    expiration { days = 14 }
    noncurrent_version_expiration { noncurrent_days = 7 }
  }
}

resource "aws_cloudwatch_log_group" "boxes" {
  name              = "/xenia/boxes"
  retention_in_days = 14
}

resource "aws_ecr_repository" "app" {
  for_each             = var.allowed_repos
  name                 = "xenia/${split("/", each.key)[1]}"
  force_delete         = true
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = false }
}
resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = var.allowed_repos
  repository = aws_ecr_repository.app[each.key].name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep the last 20 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_ssm_parameter" "zone_name" {
  name  = "/xenia/platform/zone-name"
  type  = "String"
  value = var.zone_name
}
