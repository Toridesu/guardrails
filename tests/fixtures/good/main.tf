# 違反のない Terraform（Checkov のテスト用）。apply しない。
# bad/ と同じ種類のリソースを、統制に沿った設定で書く。ここで1つでも失敗すれば誤検知。

resource "aws_ebs_volume" "encrypted" {
  availability_zone = "ap-northeast-1a"
  size              = 8
  encrypted         = true
}

resource "aws_instance" "encrypted_root" {
  ami           = "ami-00000000000000000"
  instance_type = "t3.micro"

  root_block_device {
    encrypted = true
  }
}

resource "aws_security_group" "admin_from_office" {
  name        = "demo-admin-from-office"
  description = "good example"

  ingress {
    description = "ssh from office only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["203.0.113.0/24"]
  }
}

# ::/0 でも22番を含まない範囲なら通る
resource "aws_vpc_security_group_ingress_rule" "https_ipv6" {
  security_group_id = aws_security_group.admin_from_office.id
  cidr_ipv6         = "::/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# IPv6 の特定の範囲からなら22番でも通る
resource "aws_vpc_security_group_ingress_rule" "ssh_ipv6_office" {
  security_group_id = aws_security_group.admin_from_office.id
  cidr_ipv6         = "2001:db8::/32"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_cloudtrail" "strong" {
  name                       = "demo-strong-trail"
  s3_bucket_name             = "demo-bucket"
  is_multi_region_trail      = true
  enable_log_file_validation = true
}

resource "aws_s3_account_public_access_block" "strong" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
