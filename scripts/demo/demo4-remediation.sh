#!/usr/bin/env bash
# デモ4（C10）：SSH を全世界に開けると、Config が検知し、SSM Automation が自動で閉じる。
# 何にも付けていない空のセキュリティグループで試すので、実際に公開されるものはない。
# 終わったら（途中で Ctrl+C で止めても）セキュリティグループを消す。
# ここで出す時間は目安。正確な時間は、何回か実行したあと scripts/measure_remediation.py で測る。
# 使い方：scripts/demo/demo4-remediation.sh（AWS を呼ばずに流れだけ見るなら DRY_RUN=1 を付ける）
source "$(dirname "$0")/lib.sh"
require WORKLOAD_PROFILE

W=(--profile "$WORKLOAD_PROFILE" --region "$PRIMARY_REGION")
TIMEOUT_SEC="${TIMEOUT_SEC:-900}" # 15分待っても閉じなければ失敗にする
INTERVAL_SEC="${INTERVAL_SEC:-10}"
sg=""

cleanup() {
  [[ -z "$sg" ]] && return 0
  step "片付け"
  run aws "${W[@]}" ec2 delete-security-group --group-id "$sg" ||
    printf '  ⚠ 消せなかった。手で消す：%s\n' "$sg"
  sg=""
}
trap cleanup EXIT

step "実行するのは誰か"
whoami_check "$WORKLOAD_PROFILE"

step "空のセキュリティグループを作る"
vpc="${VPC_ID:-}"
if [[ -z "$vpc" ]]; then
  must aws "${W[@]}" ec2 describe-vpcs --filters Name=is-default,Values=true \
    --query 'Vpcs[0].VpcId' --output text
  vpc="$_out"
  if [[ "$vpc" == None ]]; then
    echo "  既定の VPC がない。demo.env に VPC_ID を書く"
    exit 1
  fi
fi
must aws "${W[@]}" ec2 create-security-group \
  --group-name "guardrails-demo4-$(date +%Y%m%d-%H%M%S)" \
  --description "guardrails demo4 (deleted after the demo)" \
  --vpc-id "$vpc" --query GroupId --output text
sg="$_out"
printf '  作った：%s\n' "$sg"

step "SSH（22番）を 0.0.0.0/0 に開ける（C10 の違反）"
must aws "${W[@]}" ec2 authorize-security-group-ingress \
  --group-id "$sg" --protocol tcp --port 22 --cidr 0.0.0.0/0
opened_at=$(date +%s)
printf '  開けた時刻：%s\n' "$(date '+%H:%M:%S')"

step "閉じられるまで待つ（${INTERVAL_SEC} 秒ごとに確認、最大 $((TIMEOUT_SEC / 60)) 分）"
# 0.0.0.0/0 から入れる規則の数。0 になれば閉じられた
query="length(SecurityGroupRules[?IsEgress==\`false\` && CidrIpv4=='0.0.0.0/0'])"
printf '  $ aws %s ec2 describe-security-group-rules --filters Name=group-id,Values=%s --query "%s"\n' \
  "${W[*]}" "$sg" "$query"
if [[ "$DRY_RUN" != 1 ]]; then
  while :; do
    _out="$(aws "${W[@]}" ec2 describe-security-group-rules \
      --filters Name=group-id,Values="$sg" --query "$query" --output text 2>&1)"
    elapsed=$(($(date +%s) - opened_at))
    if [[ "$_out" == 0 ]]; then
      printf '\n'
      _out=""
      ok "自動で閉じられた（約 ${elapsed} 秒、時刻 $(date '+%H:%M:%S')）"
      break
    fi
    if ((elapsed >= TIMEOUT_SEC)); then
      printf '\n'
      _out="0.0.0.0/0 から入れる規則の数：$_out"
      ng "${TIMEOUT_SEC} 秒待っても閉じられなかった（Config ルール c10-restricted-ssh と修復の履歴を見る）"
      break
    fi
    printf '\r  経過 %4d 秒（まだ開いている）' "$elapsed"
    sleep "$INTERVAL_SEC"
  done
fi

cleanup
trap - EXIT
summary
