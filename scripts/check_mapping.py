#!/usr/bin/env python3
"""controls.yaml と実装がずれていないかを確かめる。ずれていれば終了コード1で終わる。

確かめること
- 統制 ID が C01 の形で、重複していない
- controls.yaml が参照する Sid、Config ルール名、Security Hub のコントロール、
  Terraform のリソース、SSM ドキュメントがコードに実在する
- 逆向き：統制 ID で始まる SCP・RCP の Sid と Config ルールが、どれかの統制から参照されている
- 参照の先頭の統制 ID（C04DenyXxx の C04 など）が、参照している統制と一致する
"""

from __future__ import annotations

import re
import sys

from controls_lib import ROOT, UNCHECKED, CodeIndex, iter_refs, load_controls

ID_PATTERN = re.compile(r"^C\d{2}$")
PREFIXED = re.compile(r"^[Cc](\d{2})")  # C04DenyXxx、c04-encrypted-volumes
CHECKOV_PREFIXED = re.compile(r"_C(\d{2})_")  # CKV2_GR_C04_1


def control_prefix(kind: str, value: str) -> str | None:
    """参照の名前に埋め込まれた統制 ID（なければ None）。"""
    if kind in ("scp", "rcp", "config_rule"):
        m = PREFIXED.match(value)
    elif kind == "checkov":
        m = CHECKOV_PREFIXED.search(value)
    else:
        return None
    return f"C{m.group(1)}" if m else None


def main() -> int:
    data = load_controls()
    controls = data.get("controls") or []
    index = CodeIndex()
    errors: list[str] = []
    referenced: dict[tuple[str, str], str] = {}
    checked = 0

    seen_ids: set[str] = set()
    for control in controls:
        cid = control.get("id", "")
        if not ID_PATTERN.match(cid):
            errors.append(f"{cid or '(ID なし)'}: ID は C01 の形にする")
        if cid in seen_ids:
            errors.append(f"{cid}: ID が重複している")
        seen_ids.add(cid)
        if not control.get("requirement"):
            errors.append(f"{cid}: requirement がない")

        try:
            refs = list(iter_refs(control, index))
        except ValueError as e:
            errors.append(f"{cid}: {e}")
            continue

        for field, ref in refs:
            if ref.kind in UNCHECKED:
                continue
            checked += 1
            referenced[(ref.kind, ref.value)] = cid
            if ref.location is None:
                errors.append(f"{cid}.{field}: {ref.kind} '{ref.value}' がコードにない（Checkov は .checkov.yaml で未有効）")
            prefix = control_prefix(ref.kind, ref.value)
            if prefix and prefix != cid:
                errors.append(f"{cid}.{field}: '{ref.value}' は別の統制（{prefix}）の ID を含んでいる")

    # 逆向き：コードにあるのに対応表から漏れているもの
    orphans = [("scp", sid) for sid in index.scp_sids if PREFIXED.match(sid)]
    orphans += [("rcp", sid) for sid in index.rcp_sids if PREFIXED.match(sid)]
    orphans += [("config_rule", name) for name in index.config_rule_names()]
    orphans += [("checkov", cid) for cid in index.checkov_enabled]  # 有効なチェックは全部
    for kind, value in orphans:
        if (kind, value) not in referenced:
            errors.append(f"{kind} '{value}' はコードにあるが、controls.yaml のどの統制からも参照されていない")

    if errors:
        print(f"NG: {len(errors)} 件のずれ（{ROOT / 'controls' / 'controls.yaml'}）")
        for e in errors:
            print(f"  - {e}")
        return 1
    print(f"OK: 統制 {len(controls)} 件、コードへの参照 {checked} 件がすべて実在する")
    return 0


if __name__ == "__main__":
    sys.exit(main())
