#!/usr/bin/env python3
"""controls.yaml から docs/mapping.md（要件対応表）を生成する。

使い方
  python scripts/gen_mapping.py          # docs/mapping.md を書き出す
  python scripts/gen_mapping.py --check  # 書き出さずに、今のファイルと一致するかだけ見る（CI 用）
"""

from __future__ import annotations

import argparse
import os
import sys

from controls_lib import KINDS, ROOT, CodeIndex, Ref, load_controls

OUTPUT = ROOT / "docs" / "mapping.md"


def cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ")


def render_ref(ref: Ref) -> str:
    if ref.kind == "text":
        return cell(ref.value)
    if ref.kind == "manual":
        return f"{KINDS['manual']}：{cell(ref.value)}"
    label = KINDS[ref.kind]
    if ref.location is None:
        return f"{label} `{ref.value}`（コードになし）"
    link = os.path.relpath(ref.location, OUTPUT.parent).replace(os.sep, "/")
    return f"{label} [`{ref.value}`]({link})"


def render_refs(control: dict, fields: tuple[str, ...], index: CodeIndex) -> str:
    items = [render_ref(index.resolve(i)) for f in fields for i in (control.get(f) or [])]
    return "<br>".join(items) if items else "なし"


def render_nist(control: dict) -> str:
    parts = list(control.get("nist_800_53") or [])
    parts += [f"800-63B-4 {x}" for x in control.get("nist_800_63b") or []]
    return "<br>".join(str(p) for p in parts) if parts else "なし"


def render(data: dict) -> str:
    index = CodeIndex()
    standards = data.get("standards") or {}
    lines = [
        "# 要件対応表",
        "",
        "<!-- このファイルは scripts/gen_mapping.py が controls/controls.yaml から生成する。手で編集しない。 -->",
        "",
        f"- FISC 安全対策基準：{standards.get('fisc', '未定')}",
        f"- NIST：{standards.get('nist_800_53', '')}、{standards.get('nist_800_63b', '')}",
        "- 実装の欄のリンクは、その統制を実装しているファイル。リンクの実在は scripts/check_mapping.py が CI で確かめる。",
        "",
        "| ID | 要件 | 防止 | 検知・修復 | 証跡 | NIST | FISC |",
        "|---|---|---|---|---|---|---|",
    ]
    notes = []
    for c in data.get("controls") or []:
        fisc = "<br>".join(str(x) for x in c.get("fisc") or []) or "（記入）"
        lines.append(
            "| "
            + " | ".join(
                [
                    c["id"],
                    cell(c["requirement"]),
                    render_refs(c, ("prevent",), index),
                    render_refs(c, ("detect", "remediate"), index),
                    render_refs(c, ("evidence",), index),
                    render_nist(c),
                    fisc,
                ]
            )
            + " |"
        )
        if c.get("notes"):
            notes.append(f"- **{c['id']}**：{c['notes'].strip()}")
    if notes:
        lines += ["", "## 注記", "", *notes]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="生成結果が docs/mapping.md と一致するかだけ確かめる")
    args = parser.parse_args()

    content = render(load_controls())
    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != content:
            print("NG: docs/mapping.md が controls.yaml と一致しない。python scripts/gen_mapping.py で作り直す")
            return 1
        print("OK: docs/mapping.md は controls.yaml と一致している")
        return 0
    OUTPUT.write_text(content, encoding="utf-8")
    print(f"書き出した: {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
