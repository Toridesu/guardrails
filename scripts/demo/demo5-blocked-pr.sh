#!/usr/bin/env bash
# デモ5（C11）：違反を含むプルリクエストは、CI が失敗してマージできない。
# tests/fixtures/bad（違反ありのサンプル）を terraform/ の下に置いたブランチを作り、プルリクエストを出す。
#
# 前提：GitHub にリポジトリがあり、gh でログインしている。
#       main のブランチ保護で、CI の2つのジョブを必須にしている。
# 安全のため、マージは試さない。GitHub が「マージできない（BLOCKED）」と判定しているかを見る。
#   - BLOCKED  ：CI が失敗し、ブランチ保護で止まっている（期待どおり）
#   - UNSTABLE ：CI は失敗したが、マージはできてしまう（ブランチ保護の設定が足りない）
# 終わったらプルリクエストを閉じ、ブランチを消す。KEEP=1 なら残す（録画やスクリーンショット用）。
# 使い方：scripts/demo/demo5-blocked-pr.sh（GitHub を呼ばずに流れだけ見るなら DRY_RUN=1 を付ける）
source "$(dirname "$0")/lib.sh"

base="${BASE_BRANCH:-main}"
branch="demo5-violation-$(date +%Y%m%d-%H%M%S)"
if ! top="$(git -C "$DEMO_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
  if [[ "$DRY_RUN" != 1 ]]; then
    echo "git のリポジトリの中で実行する"
    exit 1
  fi
  top="$DEMO_DIR/../.."
fi
cd "$top" || exit 1

step "作業ツリーに変更がなく、$base にいること"
if [[ "$DRY_RUN" != 1 ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "  コミットしていない変更がある。コミットするか stash してから実行する"
    exit 1
  fi
  if [[ "$(git branch --show-current)" != "$base" ]]; then
    echo "  $base ブランチで実行する"
    exit 1
  fi
fi
ok "$base にいて、変更なし"

step "違反を含むブランチを作り、push する"
must git switch -c "$branch"
must mkdir -p terraform/demo5-violation
must cp tests/fixtures/bad/main.tf terraform/demo5-violation/main.tf
must git add terraform/demo5-violation
must git commit -m "demo5: 違反を含む変更（マージできないことを確かめる）"
must git push -u origin "$branch"
must git switch "$base"

step "プルリクエストを出す"
must gh pr create --base "$base" --head "$branch" \
  --title "demo5: 違反を含む変更（マージしない）" \
  --body "デモ5（C11）。CI の Checkov が失敗し、ブランチ保護でマージできないことを確かめる。"
pr="$(tail -1 <<<"$_out")" # gh は最後の行にプルリクエストの URL を出す
printf '  %s\n' "$pr"

step "CI の結果を待つ"
printf '  $ gh pr checks %s --watch\n' "$pr"
if [[ "$DRY_RUN" != 1 ]]; then
  # 出した直後はチェックがまだ登録されていないので、出てくるまで待つ（最大2分）
  for _ in $(seq 24); do
    n="$(gh pr checks "$pr" --json name --jq length 2>/dev/null)"
    [[ "${n:-0}" =~ ^[1-9] ]] && break
    sleep 5
  done
  gh pr checks "$pr" --watch --interval 10 # 失敗があると終了コードが0以外になる（ここでは期待どおり）

  _out="$(gh pr checks "$pr" --json name,bucket --jq '.[] | "\(.bucket) \(.name)"' 2>&1)"
  if grep -qE '^fail .*checkov' <<<"$_out"; then
    _out=""
    ok "Checkov のジョブが失敗した"
  else
    ng "Checkov のジョブが失敗していない"
  fi
fi

step "マージできない状態か（ブランチ保護）"
if [[ "$DRY_RUN" != 1 ]]; then
  # 判定に少し時間がかかることがある（UNKNOWN）
  for _ in $(seq 6); do
    run gh pr view "$pr" --json mergeStateStatus --jq .mergeStateStatus
    [[ "$_out" != UNKNOWN ]] && break
    sleep 5
  done
  case "$_out" in
  BLOCKED) ok "マージできない（BLOCKED）" ;;
  UNSTABLE) ng "CI は失敗したが、マージできてしまう（UNSTABLE）。ブランチ保護で CI を必須にする" ;;
  *) ng "想定外の状態：$_out" ;;
  esac
else
  run gh pr view "$pr" --json mergeStateStatus --jq .mergeStateStatus
fi

step "片付け"
if [[ "${KEEP:-0}" == 1 ]]; then
  printf '  KEEP=1 なので残す。あとで消す：gh pr close %s --delete-branch\n' "$pr"
else
  run gh pr close "$pr" --delete-branch ||
    printf '  ⚠ 閉じられなかった。手で閉じる：%s\n' "$pr"
fi

summary
