#!/usr/bin/env bash
# デモ3（C04〜C07）：アカウントの基本設定を崩せない。
# C09（ルートの操作の拒否）は、ルートの認証情報を消しているのでデモしない。
# 使い方：scripts/demo/demo3-baseline.sh（AWS を呼ばずに流れだけ見るなら DRY_RUN=1 を付ける）
source "$(dirname "$0")/lib.sh"
require WORKLOAD_PROFILE SECURITY_PROFILE LOG_BUCKET

W=(--profile "$WORKLOAD_PROFILE" --region "$PRIMARY_REGION")
S=(--profile "$SECURITY_PROFILE" --region "$PRIMARY_REGION")

step "実行するのは誰か"
whoami_check "$WORKLOAD_PROFILE"
whoami_check "$SECURITY_PROFILE"
account="$(account_id "$WORKLOAD_PROFILE")"

step "EBS の既定の暗号化を切れない（C04DenyDisableEbsDefaultEncryption）"
expect_denied "既定の暗号化を無効にする" \
  aws "${W[@]}" ec2 disable-ebs-encryption-by-default --dry-run

step "S3 のパブリックアクセスブロックを変えられない（C05DenyAccountPublicAccessBlockChange）"
# いまと同じ値（すべて true）を書く。SCP が効いていなくても何も変わらない
expect_denied "アカウントの設定を書き換える" \
  aws "${W[@]}" s3control put-public-access-block --account-id "$account" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

step "S3 は暗号化していない通信では使えない（C06DenyS3WithoutTLS、security）"
expect_allowed "HTTPS で一覧を取る" \
  aws "${S[@]}" s3api list-objects-v2 --bucket "$LOG_BUCKET" --max-items 1
expect_denied "HTTP で一覧を取る" \
  aws "${S[@]}" s3api list-objects-v2 --bucket "$LOG_BUCKET" --max-items 1 \
  --endpoint-url "http://s3.${PRIMARY_REGION}.amazonaws.com"

step "IAM ユーザーと長期のアクセスキーを作れない（C07DenyLongTermCredentials）"
expect_denied "IAM ユーザーを作る" \
  aws "${W[@]}" iam create-user --user-name guardrails-demo-user
undo_if_allowed aws "${W[@]}" iam delete-user --user-name guardrails-demo-user
# 存在しないユーザーを使う。SCP が効いていなければ「見つからない」で終わる
expect_denied "アクセスキーを作る" \
  aws "${W[@]}" iam create-access-key --user-name guardrails-demo-nonexistent

summary
