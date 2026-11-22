#!/usr/bin/env bash
# デモ2（C02・C03）：監査ログと構成の記録を、止めることも消すこともできない。
# 管理者権限（AdministratorAccess）を持つ Identity Center のユーザーでも拒否される。
# 使い方：scripts/demo/demo2-logging.sh（AWS を呼ばずに流れだけ見るなら DRY_RUN=1 を付ける）
source "$(dirname "$0")/lib.sh"
require WORKLOAD_PROFILE SECURITY_PROFILE LOG_BUCKET

W=(--profile "$WORKLOAD_PROFILE" --region "$PRIMARY_REGION")
S=(--profile "$SECURITY_PROFILE" --region "$PRIMARY_REGION")

step "実行するのは誰か"
whoami_check "$WORKLOAD_PROFILE"
whoami_check "$SECURITY_PROFILE"

# 存在しない名前を使う。SCP が効いていなければ「見つからない」で終わり、何も止まらない
step "Config の記録を止められない（C03DenyConfigChanges、workload）"
expect_denied "記録を止める" \
  aws "${W[@]}" configservice stop-configuration-recorder \
  --configuration-recorder-name guardrails-demo-nonexistent
expect_denied "ルールを消す" \
  aws "${W[@]}" configservice delete-config-rule \
  --config-rule-name guardrails-demo-nonexistent

step "CloudTrail を止められない（C02DenyCloudTrailChanges、workload）"
expect_denied "証跡を止める" \
  aws "${W[@]}" cloudtrail stop-logging --name guardrails-demo-nonexistent

step "ログバケットに手を出せない（C02ProtectLogBucket、security）"
# 存在しないキーを消そうとする。SCP が効いていなければ削除マーカーが1つ増えるだけ
expect_denied "ログを消す" \
  aws "${S[@]}" s3api delete-object --bucket "$LOG_BUCKET" --key guardrails-demo/nonexistent
# いまと同じ値（Enabled）を書く。SCP が効いていなくても何も変わらない
expect_denied "バージョニングの設定を変える" \
  aws "${S[@]}" s3api put-bucket-versioning --bucket "$LOG_BUCKET" \
  --versioning-configuration Status=Enabled

summary
