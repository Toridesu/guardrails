# policies フォルダのテスト。AWS には接続しない（mock_provider が AWS の代わりに偽の値を返す）。
# 実行：terraform -chdir=terraform/policies init -backend=false && terraform -chdir=terraform/policies test
#
# 確かめること
# - SCP 3本と RCP 1本が、組織のルートに付く
# - ポリシーの中の ${...} がすべて埋まり、文字数が上限（5,120）に収まる
# - 例外の管理者ロール、リージョン、ログバケットの名前が、変数どおりに入る
# - アカウントの既定設定（C04、C05、C12）が、統制どおりの値になる

mock_provider "aws" {
  # 組織のルート ID を決めておく（決めないと偽の値でルートの一覧が空になり、roots[0] が取れない）
  override_data {
    target = data.aws_organizations_organization.this
    values = {
      roots = [{ id = "r-test", arn = "arn:aws:organizations::000000000000:root/o-test/r-test", name = "Root", policy_types = [] }]
    }
  }
}

mock_provider "aws" {
  alias = "security"
}

mock_provider "aws" {
  alias = "workload"
}

variables {
  security_account_id = "111111111111"
  workload_account_id = "222222222222"
  log_bucket_name     = "guardrails-logs-test"
}

run "attached_to_root" {
  # mock なので apply しても AWS は変わらない。付け先の ID などの計算値まで確かめるため apply にする
  command = apply

  assert {
    condition     = length(aws_organizations_policy.scp) == 3 && length(aws_organizations_policy.rcp) == 1
    error_message = "SCP は3本、RCP は1本のはず"
  }
  assert {
    condition     = alltrue([for p in aws_organizations_policy.scp : p.type == "SERVICE_CONTROL_POLICY"])
    error_message = "scp の種類が SERVICE_CONTROL_POLICY になっていない"
  }
  assert {
    condition     = alltrue([for p in aws_organizations_policy.rcp : p.type == "RESOURCE_CONTROL_POLICY"])
    error_message = "rcp の種類が RESOURCE_CONTROL_POLICY になっていない"
  }
  assert {
    condition = alltrue([
      for a in merge(aws_organizations_policy_attachment.scp, aws_organizations_policy_attachment.rcp) :
      a.target_id == "r-test"
    ])
    error_message = "SCP と RCP は、すべて組織のルートに付けるはず"
  }
}

run "content_is_rendered" {
  command = plan

  assert {
    condition = alltrue([
      for p in merge(aws_organizations_policy.scp, aws_organizations_policy.rcp) :
      !strcontains(p.content, "$${")
    ])
    error_message = "ポリシーに埋まっていない $${...} が残っている"
  }
  assert {
    condition     = alltrue([for p in aws_organizations_policy.scp : length(p.content) <= 5120])
    error_message = "SCP が 5,120 文字を超えている"
  }
  # C01：東京と大阪以外を拒否し、大阪では Bedrock の推論と STS 以外を拒否する
  assert {
    condition     = jsondecode(aws_organizations_policy.scp["guardrails-c01-region"].content).Statement[0].Condition.StringNotEquals["aws:RequestedRegion"] == ["ap-northeast-1", "ap-northeast-3"]
    error_message = "C01：許可するリージョンが東京と大阪になっていない"
  }
  assert {
    condition = (
      jsondecode(aws_organizations_policy.scp["guardrails-c01-region"].content).Statement[1].Condition.StringEquals["aws:RequestedRegion"] == "ap-northeast-3"
      && contains(jsondecode(aws_organizations_policy.scp["guardrails-c01-region"].content).Statement[1].NotAction, "bedrock:InvokeModel")
    )
    error_message = "C01：大阪で Bedrock の推論だけを許す文になっていない"
  }
  # C02：ログバケットの保護が、変数で渡したバケットを指す
  assert {
    condition = contains(
      jsondecode(aws_organizations_policy.scp["guardrails-c02-c03-logging"].content).Statement[1].Resource,
      "arn:aws:s3:::guardrails-logs-test/*"
    )
    error_message = "C02：ログバケットの名前が SCP に入っていない"
  }
}

run "admin_role_is_the_only_exception" {
  command = plan

  # 例外の名前を変えると、例外を持つ文がすべてその名前になること（書き間違いや取り残しを見つける）
  variables {
    admin_role_name = "TestAdminRole"
  }

  assert {
    condition = alltrue(flatten([
      for key in ["guardrails-c02-c03-logging", "guardrails-c04-c09-baseline"] : [
        for s in jsondecode(aws_organizations_policy.scp[key].content).Statement :
        s.Condition.ArnNotLike["aws:PrincipalArn"] == "arn:aws:iam::*:role/TestAdminRole"
        if s.Sid != "C09DenyRootUser"
      ]
    ]))
    error_message = "C02〜C07 の文に、管理者ロールの例外が入っていない（または名前が違う）"
  }
  assert {
    condition = alltrue([
      for p in aws_organizations_policy.scp : !strcontains(p.content, "OrganizationAccountAccessRole")
    ])
    error_message = "既定のロール名が、変数を通さずに書かれている"
  }
  # C09 のルートの拒否には例外を付けない
  assert {
    condition = alltrue([
      for s in jsondecode(aws_organizations_policy.scp["guardrails-c04-c09-baseline"].content).Statement :
      !can(s.Condition.ArnNotLike) if s.Sid == "C09DenyRootUser"
    ])
    error_message = "C09：ルートの拒否に例外が付いている"
  }
}

run "account_baseline" {
  command = plan

  # アカウントの既定設定のモジュールだけを、単体で確かめる
  module {
    source = "./account_baseline"
  }

  assert {
    condition     = aws_ebs_encryption_by_default.this.enabled
    error_message = "C04：EBS の既定の暗号化が有効になっていない"
  }
  assert {
    condition = alltrue([
      aws_s3_account_public_access_block.this.block_public_acls,
      aws_s3_account_public_access_block.this.block_public_policy,
      aws_s3_account_public_access_block.this.ignore_public_acls,
      aws_s3_account_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "C05：パブリックアクセスブロックの4項目が、すべて有効になっていない"
  }
  assert {
    condition = (
      aws_iam_account_password_policy.this.minimum_password_length >= 15
      && !aws_iam_account_password_policy.this.require_lowercase_characters
      && !aws_iam_account_password_policy.this.require_uppercase_characters
      && !aws_iam_account_password_policy.this.require_numbers
      && !aws_iam_account_password_policy.this.require_symbols
    )
    error_message = "C12：パスワードポリシーが 800-63B-4 に合わせた設定（文字種なし、15文字以上）になっていない"
  }
}
