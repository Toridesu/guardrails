#!/usr/bin/env python3
"""SCP・RCP で拒否されるかを、手元でまねて確かめる（簡易版。AWS には接続しない）。

terraform/policies の SCP と RCP を読み、tests/policy_cases.yaml の操作ごとに
拒否されるかを判定して、期待どおりかを確かめる。デモ1〜3と同じ操作を入れてある。

まねているのは、このリポジトリのポリシーが使う範囲だけ。
- 文は Deny だけ（SCP の FullAWSAccess と、IAM の権限で許可されている前提）
- Action / NotAction、Resource / NotResource（ワイルドカードの * と ?）
- Condition：StringEquals、StringNotEquals、StringLike、ArnLike、ArnNotLike、Bool と、その IfExists
  - 1つのキーに値が複数あれば「どれかに一致」。否定の演算子（Not が付くもの）は「どれにも一致しない」
  - リクエストにキーがないとき、否定の演算子と IfExists は真、それ以外は偽
知らない欄や演算子があれば、黙って間違えないように、そこで止める。
本物の評価と完全には一致しないので、結果は「本物の AWS で確かめるまでの目安」として扱う。

使い方（リポジトリのルートで）:
  python scripts/test_policy_cases.py
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from fnmatch import fnmatchcase
from pathlib import Path
from string import Template

import yaml

ROOT = Path(__file__).resolve().parent.parent
POLICY_DIR = ROOT / "terraform" / "policies"
CASES_FILE = ROOT / "tests" / "policy_cases.yaml"

KNOWN_FIELDS = {"Sid", "Effect", "Action", "NotAction", "Resource", "NotResource", "Condition", "Principal"}


def _as_list(value) -> list[str]:
    return value if isinstance(value, list) else [value]


@dataclass
class Statement:
    sid: str
    kind: str  # SCP か RCP
    file: str
    doc: dict


def load_statements(policy_dir: Path, variables: dict[str, str]) -> list[Statement]:
    """SCP と RCP の JSON を読み、${...} を埋めて、文の一覧にする（Terraform の templatefile と同じ）。"""
    statements = []
    for kind in ("scp", "rcp"):
        for path in sorted((policy_dir / kind).glob("*.json")):
            text = Template(path.read_text(encoding="utf-8")).substitute(variables)
            for s in json.loads(text)["Statement"]:
                unknown = set(s) - KNOWN_FIELDS
                if unknown:
                    sys.exit(f"{path.name} {s.get('Sid')}: まねられない欄がある: {sorted(unknown)}")
                if s["Effect"] != "Deny":
                    sys.exit(f"{path.name} {s.get('Sid')}: Deny 以外の文はまねない")
                statements.append(Statement(s["Sid"], kind.upper(), path.name, s))
    return statements


def _match_action(action: str, patterns: list[str]) -> bool:
    return any(fnmatchcase(action.lower(), p.lower()) for p in patterns)  # 操作名は大文字小文字を区別しない


def _match_resource(resource: str, patterns: list[str]) -> bool:
    return any(fnmatchcase(resource, p) for p in patterns)


# 演算子 → (値の比べ方, 否定か)
OPERATORS = {
    "StringEquals": (lambda v, p: v == p, False),
    "StringNotEquals": (lambda v, p: v == p, True),
    "StringLike": (fnmatchcase, False),
    "StringNotLike": (fnmatchcase, True),
    "ArnLike": (fnmatchcase, False),
    "ArnNotLike": (fnmatchcase, True),
    "Bool": (lambda v, p: v.lower() == p.lower(), False),
}


def _condition_holds(condition: dict, context: dict[str, str]) -> bool:
    for op_name, keys in condition.items():
        if_exists = op_name.endswith("IfExists")
        base = op_name.removesuffix("IfExists")
        if base not in OPERATORS:
            raise ValueError(f"まねられない演算子: {op_name}")
        compare, negated = OPERATORS[base]
        for key, values in keys.items():
            actual = context.get(key)
            if actual is None:
                holds = if_exists or negated
            else:
                hit = any(compare(actual, p) for p in _as_list(values))
                holds = not hit if negated else hit
            if not holds:
                return False  # 条件は全部そろって初めて成り立つ
    return True


def denying(statements: list[Statement], request: dict) -> list[Statement]:
    """このリクエストを拒否する文の一覧。"""
    result = []
    for st in statements:
        s = st.doc
        if "Action" in s and not _match_action(request["action"], _as_list(s["Action"])):
            continue
        if "NotAction" in s and _match_action(request["action"], _as_list(s["NotAction"])):
            continue
        if "Resource" in s and not _match_resource(request["resource"], _as_list(s["Resource"])):
            continue
        if "NotResource" in s and _match_resource(request["resource"], _as_list(s["NotResource"])):
            continue
        if not _condition_holds(s.get("Condition") or {}, request["context"]):
            continue
        result.append(st)
    return result


def build_request(case: dict, defaults: dict, principals: dict[str, str]) -> dict:
    c = {**defaults, **case}
    return {
        "action": c["action"],
        "resource": c["resource"],
        "context": {
            "aws:RequestedRegion": c["region"],
            "aws:PrincipalArn": principals[c["principal"]],
            "aws:SecureTransport": "true" if c["secure_transport"] else "false",
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--policy-dir", type=Path, default=POLICY_DIR, help="scp/ と rcp/ があるフォルダ（テスト用）")
    args = ap.parse_args()

    spec = yaml.safe_load(CASES_FILE.read_text(encoding="utf-8"))
    statements = load_statements(args.policy_dir, spec["vars"])
    sids = {st.sid for st in statements}
    ok = True
    used: set[str] = set()

    for case in spec["cases"]:
        request = build_request(case, spec["defaults"], spec["principals"])
        try:
            hits = denying(statements, request)
        except ValueError as e:
            sys.exit(f"{case['name']}：{e}（まねるなら、このスクリプトの OPERATORS に足す）")
        hit_sids = [st.sid for st in hits]
        used |= set(hit_sids)
        who = case.get("principal", spec["defaults"]["principal"])
        label = f"{case['name']}（{request['action']}、{request['context']['aws:RequestedRegion']}、{who}）"
        expected_by = case.get("by")
        if expected_by and expected_by not in sids:
            ok = False
            print(f"NG  {label}：by の {expected_by} はポリシーにない")
            continue

        if case["expect"] == "deny":
            good = bool(hits) and (not expected_by or expected_by in hit_sids)
        else:
            good = not hits
        result = f"拒否（{', '.join(hit_sids)}）" if hits else "拒否されない"
        if good:
            print(f"OK  {label} → {result}")
        else:
            ok = False
            want = f"拒否（{expected_by}）" if case["expect"] == "deny" and expected_by else (
                "拒否" if case["expect"] == "deny" else "拒否されない")
            print(f"NG  {label} → {result}（期待：{want}）")

    # どの文も、少なくとも1つのケースで拒否していること（テストのない文を残さない）
    unused = sorted(sids - used)
    if unused:
        ok = False
        print(f"\nNG  一度も拒否していない文がある（ケースを足す）：{', '.join(unused)}")
    print(f"\n{len(spec['cases'])} 件、文 {len(sids) - len(unused)}/{len(sids)} 本を使った：{'すべて期待どおり' if ok else '期待と違うものがある'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
