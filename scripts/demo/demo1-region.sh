#!/usr/bin/env bash
# デモ1（C01）：東京と大阪以外のリージョンは使えない。大阪は Bedrock の推論だけ。
# 使い方：scripts/demo/demo1-region.sh（AWS を呼ばずに流れだけ見るなら DRY_RUN=1 を付ける）
source "$(dirname "$0")/lib.sh"
require WORKLOAD_PROFILE

W=(--profile "$WORKLOAD_PROFILE")

step "実行するのは誰か"
whoami_check "$WORKLOAD_PROFILE"

step "東京は使える"
expect_allowed "VPC の一覧（東京）" \
  aws "${W[@]}" --region "$PRIMARY_REGION" ec2 describe-vpcs --dry-run

step "許可していないリージョンは使えない（C01DenyOutsideAllowedRegions）"
for region in us-east-1 eu-west-1; do
  expect_denied "VPC の一覧（$region）" \
    aws "${W[@]}" --region "$region" ec2 describe-vpcs --dry-run
done

step "グローバルサービスは、リージョン指定に関係なく使える"
expect_allowed "IAM のアカウント別名（us-east-1 を指定）" \
  aws "${W[@]}" --region us-east-1 iam list-account-aliases

step "大阪は Bedrock の推論以外は使えない（C01DenyOsakaExceptBedrock）"
expect_denied "VPC の一覧（大阪）" \
  aws "${W[@]}" --region "$SECONDARY_REGION" ec2 describe-vpcs --dry-run
# 大阪で推論できることは、P3 で Bedrock を使うときに確かめる

summary
