# 違反を含む Terraform（Checkov のテスト用。デモ5のプルリクエストにも使う）。apply しない。
# .checkov.yaml の各チェックが、ここで少なくとも1回は失敗することを scripts/test_checkov_fixtures.py が確かめる。

# C04: 暗号化なしの EBS（CKV_AWS_3、CKV2_GR_C04_1）
resource "aws_ebs_volume" "unencrypted" {
  availability_zone = "ap-northeast-1a"
  size              = 8
  encrypted         = false
}

# C04: 暗号化なしのルートボリューム（CKV_AWS_8）
resource "aws_instance" "unencrypted_root" {
  ami           = "ami-00000000000000000"
  instance_type = "t3.micro"

  root_block_device {
    encrypted = false
  }
}

# C10: 0.0.0.0/0 に22番と3389番（CKV_AWS_24、CKV_AWS_25）
resource "aws_security_group" "open_admin_ports" {
  name        = "demo-open-admin-ports"
  description = "bad example"

  ingress {
    description = "ssh from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "rdp from anywhere"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# C10: ::/0 にポート範囲で22番を含めて開ける（CKV2_GR_C10_1）
resource "aws_vpc_security_group_ingress_rule" "open_ssh_ipv6_range" {
  security_group_id = aws_security_group.open_admin_ports.id
  cidr_ipv6         = "::/0"
  from_port         = 0
  to_port           = 1024
  ip_protocol       = "tcp"
}

# C02: 単一リージョンで、ログファイルの検証なし（CKV_AWS_36、CKV_AWS_67、CKV2_GR_C02_1）
resource "aws_cloudtrail" "weak" {
  name                       = "demo-weak-trail"
  s3_bucket_name             = "demo-bucket"
  is_multi_region_trail      = false
  enable_log_file_validation = false
}

# C05: アカウント単位のパブリックアクセスブロックを緩める（CKV2_GR_C05_1）
resource "aws_s3_account_public_access_block" "weak" {
  block_public_acls       = false
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
