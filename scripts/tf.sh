#!/usr/bin/env bash
# Terraform を、フォルダごとの state と共通の値を付けて実行する。
#
# 使い方（どこからでもよい）:
#   scripts/tf.sh <フォルダ> <terraform のコマンド> [引数...]
#     例：scripts/tf.sh org plan
#         scripts/tf.sh logging apply
#   scripts/tf.sh all init|plan|apply   決まった順にすべて（apply はフォルダごとに確認が出る）
#
# apply の順番：org → logging → detection → remediation → policies
#   - org が組織とアカウントを作り、その出力（アカウント ID など）をあとのフォルダが使う
#   - detection は logging のバケットと KMS キーを、remediation は detection の Config ルールを使う
#   - policies（SCP・RCP）は最後。Terraform は SCP の例外の管理者ロールで動くので前でも作れるが、
#     土台ができてから締めるほうが、失敗したときに原因を切り分けやすい
# destroy はフォルダごとに逆の順で行う（all では使えない）。
#   ログバケットは Object Lock の期間が過ぎるまで消せない。org の destroy はアカウントを組織から外そうとする
#
# 前提（どちらも git の管理外）:
#   terraform/backend.hcl   state の置き場所（backend.hcl.example を参照）
#   terraform/shared.env    自分で決める値（shared.env.example を参照）
#
# 値の渡し方：shared.env と org の出力を、TF_VAR_<変数名> の環境変数にして渡す。
#   -var-file と違い、そのフォルダが使わない値は警告なしで無視される。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"
ORDER=(org logging detection remediation policies)
# あとのフォルダに渡す org の出力
ORG_OUTPUTS=(organization_id security_account_id workload_account_id workloads_ou_id)
STATE_PREFIX="guardrails"

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

die() {
  printf 'tf.sh: %s\n' "$*" >&2
  exit 1
}

load_settings() {
  [[ -f "$TF_DIR/backend.hcl" ]] || die "terraform/backend.hcl がない（backend.hcl.example をコピーして書く）"
  [[ -f "$TF_DIR/shared.env" ]] || die "terraform/shared.env がない（shared.env.example をコピーして書く）"
  set -a # 読み込んだ値を、すべて環境変数にする
  # shellcheck source=/dev/null
  source "$TF_DIR/shared.env"
  set +a
}

tf() {
  local dir="$1"
  shift
  terraform -chdir="$TF_DIR/$dir" "$@"
}

init() {
  local dir="$1"
  shift
  tf "$dir" init -input=false \
    -backend-config="$TF_DIR/backend.hcl" \
    -backend-config="key=$STATE_PREFIX/$dir/terraform.tfstate" "$@"
}

# state の置き場所を付けて初期化していなければ、初期化する
# （CI や手元の validate は -backend=false で初期化するので、それとは別に必要）
ensure_init() {
  [[ -f "$TF_DIR/$1/.terraform/terraform.tfstate" ]] || init "$1"
}

load_org_outputs() {
  local name value
  ensure_init org
  for name in "${ORG_OUTPUTS[@]}"; do
    value="$(tf org output -raw "$name" 2>/dev/null)" ||
      die "org の出力 $name を読めない。先に scripts/tf.sh org apply を実行する"
    export "TF_VAR_$name=$value"
  done
}

run_one() {
  local dir="$1"
  shift
  [[ " ${ORDER[*]} " == *" $dir "* ]] || die "知らないフォルダ：$dir（使えるのは ${ORDER[*]} と all）"
  printf '\n######## %s: terraform %s\n' "$dir" "$*"
  if [[ "$1" == init ]]; then
    shift
    init "$dir" "$@"
    return
  fi
  ensure_init "$dir"
  [[ "$dir" == org ]] || load_org_outputs
  tf "$dir" "$@"
}

[[ $# -ge 2 ]] || usage
target="$1"
shift
load_settings

if [[ "$target" == all ]]; then
  case "$1" in
  init | plan | apply) ;;
  *) die "all で使えるのは init、plan、apply だけ（destroy はフォルダごとに逆の順で）" ;;
  esac
  for dir in "${ORDER[@]}"; do
    run_one "$dir" "$@"
  done
else
  run_one "$target" "$@"
fi
