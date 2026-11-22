# shellcheck shell=bash
# デモ共通の関数。各デモの先頭で source する。
# 設定は scripts/demo/demo.env に書く（demo.env.example をコピーして作る。git の管理外）。
#
# 方針：万一 SCP が効いていなくても、デモで環境が壊れない操作だけを使う。
#   - EC2 は --dry-run を付ける（許可なら DryRunOperation、拒否なら UnauthorizedOperation が返る）
#   - 停止や削除は、存在しない名前を相手にする（許可なら「見つからない」、拒否なら AccessDenied）
#   - 設定の変更は、いまと同じ値を書く（許可されても何も変わらない）
#   - それでも変わってしまう操作（IAM ユーザーの作成）は、拒否されなかったら元に戻す
#
# DRY_RUN=1 を付けて実行すると、AWS などを呼ばずにコマンドを表示するだけにする。

set -uo pipefail # -e は付けない。拒否される＝コマンドが失敗するのを確かめるため

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$DEMO_DIR/demo.env" ]]; then
  # shellcheck source=/dev/null
  source "$DEMO_DIR/demo.env"
fi

PRIMARY_REGION="${PRIMARY_REGION:-ap-northeast-1}"
SECONDARY_REGION="${SECONDARY_REGION:-ap-northeast-3}"
ADMIN_ROLE_NAME="${ADMIN_ROLE_NAME:-OrganizationAccountAccessRole}"
DRY_RUN="${DRY_RUN:-0}"

# 拒否されたときのエラーに含まれる文字列
DENIED='AccessDenied|UnauthorizedOperation|explicit deny'
# 失敗扱いだが、実際には許可されている（--dry-run の成功）
ALLOWED_ERRORS='DryRunOperation'

_out=""
_pass=0
_fail=0

# 設定が書かれているかを確かめる。例：require WORKLOAD_PROFILE LOG_BUCKET
require() {
  local name
  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      printf 'scripts/demo/demo.env に %s を書く（demo.env.example を参照）\n' "$name" >&2
      exit 1
    fi
  done
}

step() { printf '\n== %s\n' "$*"; }

# コマンドを表示して実行し、出力（標準出力と標準エラー）を _out に入れる
run() {
  printf '  $ %s\n' "$*"
  if [[ "$DRY_RUN" == 1 ]]; then
    _out="(DRY_RUN)"
    return 0
  fi
  _out="$("$@" 2>&1)"
}

# 失敗したら、そこでデモを止める（準備の操作に使う）
must() {
  run "$@" && return 0
  printf '  失敗したので止める：\n'
  sed 's/^/     /' <<<"$_out" | head -10
  exit 1
}

ok() {
  _pass=$((_pass + 1))
  printf '  ✅ %s\n' "$*"
}

ng() {
  _fail=$((_fail + 1))
  printf '  ❌ %s\n' "$*"
  [[ -n "$_out" ]] && sed 's/^/     /' <<<"$_out" | head -5
  return 0
}

# どの層が拒否したか（例：explicit deny in a service control policy）。出ないサービスもある
_layer() {
  grep -oiE 'explicit deny in an? [a-z -]+policy' <<<"$_out" | head -1
}

# 拒否されるはずの操作
expect_denied() {
  local what="$1" layer
  shift
  run "$@"
  [[ "$DRY_RUN" == 1 ]] && return 0
  if grep -qE "$DENIED" <<<"$_out"; then
    layer="$(_layer)"
    ok "拒否された：$what${layer:+（$layer）}"
  else
    ng "拒否されなかった：$what"
  fi
}

# 許可されるはずの操作（比較のため）
expect_allowed() {
  local what="$1" rc
  shift
  run "$@"
  rc=$?
  [[ "$DRY_RUN" == 1 ]] && return 0
  if grep -qE "$DENIED" <<<"$_out"; then
    ng "拒否された（許可のはず）：$what"
  elif [[ $rc -eq 0 ]] || grep -qE "$ALLOWED_ERRORS" <<<"$_out"; then
    ok "許可された：$what"
  else
    ng "別のエラー：$what"
  fi
}

# 直前の expect_denied が拒否されなかった（＝実際に変わってしまった）ときだけ、元に戻す
undo_if_allowed() {
  [[ "$DRY_RUN" == 1 ]] && return 0
  grep -qE "$DENIED" <<<"$_out" && return 0
  printf '  ↩ 元に戻す：%s\n' "$*"
  "$@" >/dev/null 2>&1 || printf '  ⚠ 元に戻せなかった。手で確認する\n'
}

# 誰として実行しているかを表示する。管理者ロールは SCP の例外なので、デモにならない
whoami_check() {
  local profile="$1" arn
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '  （DRY_RUN：%s の確認は省略）\n' "$profile"
    return 0
  fi
  if ! arn="$(aws --profile "$profile" sts get-caller-identity --query Arn --output text 2>&1)"; then
    printf '  %s でログインできない（aws sso login --profile %s）\n  %s\n' "$profile" "$profile" "$arn"
    exit 1
  fi
  printf '  %s: %s\n' "$profile" "$arn"
  if [[ "$arn" == *":assumed-role/$ADMIN_ROLE_NAME/"* ]]; then
    printf '  %s は SCP の例外なので拒否されない。Identity Center のプロファイルを使う\n' "$ADMIN_ROLE_NAME"
    exit 1
  fi
}

account_id() {
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "123456789012"
    return 0
  fi
  aws --profile "$1" sts get-caller-identity --query Account --output text
}

# 最後に呼ぶ。期待と違うものが1つでもあれば終了コード1
summary() {
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '\n（DRY_RUN：実際には何も呼んでいない）\n'
    return 0
  fi
  printf '\n結果：期待どおり %d 件、期待と違う %d 件\n' "$_pass" "$_fail"
  [[ $_fail -eq 0 ]]
}
