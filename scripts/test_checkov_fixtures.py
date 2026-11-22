#!/usr/bin/env python3
"""Checkov のチェックが効いているかを、サンプルの Terraform で確かめる。

- tests/fixtures/bad  : .checkov.yaml の各チェックが、少なくとも1回は失敗すること
                        （ID の打ち間違いや、効いていないカスタムポリシーをここで見つける）
- tests/fixtures/good : 1つも失敗しないこと（誤検知がないこと）

リポジトリのルートで実行する。checkov コマンドが PATH にあること。
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / ".checkov.yaml"
FIXTURES = ROOT / "tests" / "fixtures"


def failed_checks(directory: Path) -> list[tuple[str, str]]:
    """(チェック ID, リソース) の一覧を返す。"""
    proc = subprocess.run(
        ["checkov", "-d", str(directory), "--config-file", str(CONFIG), "-o", "json"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if not proc.stdout.strip():
        sys.exit(f"checkov の出力が空（終了コード {proc.returncode}）\n{proc.stderr}")
    reports = json.loads(proc.stdout)
    if isinstance(reports, dict):
        reports = [reports]
    failed = []
    for report in reports:
        for check in report.get("results", {}).get("failed_checks", []):
            failed.append((check["check_id"], check["resource"]))
    return failed


def main() -> int:
    expected = set(yaml.safe_load(CONFIG.read_text(encoding="utf-8"))["check"])
    ok = True

    bad = failed_checks(FIXTURES / "bad")
    caught = {cid for cid, _ in bad}
    missing = sorted(expected - caught)
    if missing:
        ok = False
        print(f"NG bad : 失敗しなかったチェックがある（効いていない）: {', '.join(missing)}")
    else:
        print(f"OK bad : {len(expected)} 個のチェックすべてが違反を見つけた（失敗 {len(bad)} 件）")

    good = failed_checks(FIXTURES / "good")
    if good:
        ok = False
        print("NG good: 違反のないサンプルで失敗した（誤検知）:")
        for cid, resource in good:
            print(f"  - {cid} {resource}")
    else:
        print("OK good: 失敗なし")

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
