# Should tier: restore path for box/backup.sh dumps (spec section 9). The instance role could only write
# backups (Task 6); restoring needs read access to the same bucket.
resource "aws_ssm_document" "restore" {
  name            = "xenia-restore"
  document_type   = "Command"
  document_format = "YAML"
  content         = file("${path.module}/ssm/restore.yaml")
}

data "aws_iam_policy_document" "restore_read" {
  statement {
    sid       = "ReadBackups"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${data.terraform_remote_state.platform.outputs.backup_bucket}/*"]
  }
}

resource "aws_iam_role_policy" "restore_read" {
  name   = "restore-read-backups"
  role   = "xenia-docker-box"
  policy = data.aws_iam_policy_document.restore_read.json
}