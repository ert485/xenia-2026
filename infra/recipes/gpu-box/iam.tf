data "aws_iam_policy_document" "gpu_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "gpu" {
  provider           = aws.gpu
  name               = "xenia-gpu-box"
  assume_role_policy = data.aws_iam_policy_document.gpu_trust.json
}

resource "aws_iam_instance_profile" "gpu" {
  provider = aws.gpu
  name     = "xenia-gpu-box"
  role     = aws_iam_role.gpu.name
}

resource "aws_iam_role_policy_attachment" "gpu_ssm" {
  provider   = aws.gpu
  role       = aws_iam_role.gpu.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "gpu_cwagent" {
  provider   = aws.gpu
  role       = aws_iam_role.gpu.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy_document" "gpu_params" {
  statement {
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:ca-central-1:${var.member_account_id}:parameter/xenia/gpu/*"]
  }
}

# Same account: the box's own role reads /xenia/gpu/* directly.
resource "aws_iam_role_policy" "gpu_params" {
  count    = local.same_account ? 1 : 0
  provider = aws.gpu
  name     = "read-gpu-parameters"
  role     = aws_iam_role.gpu.id
  policy   = data.aws_iam_policy_document.gpu_params.json
}

# Management-account host (deviation 9): a member-account role the GPU box assumes at boot.
data "aws_iam_policy_document" "reader_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.gpu.arn]
    }
  }
}

resource "aws_iam_role" "reader" {
  count              = local.same_account ? 0 : 1
  name               = "xenia-gpu-secrets-reader"
  assume_role_policy = data.aws_iam_policy_document.reader_trust.json
}

resource "aws_iam_role_policy" "reader" {
  count  = local.same_account ? 0 : 1
  name   = "read-gpu-parameters"
  role   = aws_iam_role.reader[0].id
  policy = data.aws_iam_policy_document.gpu_params.json
}

resource "aws_iam_role_policy" "gpu_assume_reader" {
  count    = local.same_account ? 0 : 1
  provider = aws.gpu
  name     = "assume-gpu-secrets-reader"
  role     = aws_iam_role.gpu.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Resource = aws_iam_role.reader[0].arn }]
  })
}
