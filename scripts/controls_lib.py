"""controls.yaml を読み、各参照がコードのどこにあるかを探す。

gen_mapping.py と check_mapping.py が共通で使う。
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
CONTROLS_FILE = ROOT / "controls" / "controls.yaml"
TF_DIR = ROOT / "terraform"
CHECKOV_CONFIG = ROOT / ".checkov.yaml"
CHECKOV_DIR = ROOT / "checkov"

# 参照の種類と、対応表に出すときの表示名
KINDS = {
    "scp": "SCP",
    "rcp": "RCP",
    "config_rule": "Config",
    "securityhub": "CSPM",
    "terraform": "Terraform",
    "ssm_document": "SSM",
    "checkov": "Checkov",
    "manual": "手続き",
}
# コードに実在するかを確かめない種類
UNCHECKED = {"manual", "text"}

IMPL_FIELDS = ("prevent", "detect", "remediate", "evidence")


@dataclass
class Ref:
    kind: str  # KINDS のキー、または説明だけの "text"
    value: str
    location: Path | None = None  # 見つかったファイル。見つからなければ None


def load_controls() -> dict:
    with CONTROLS_FILE.open(encoding="utf-8") as f:
        return yaml.safe_load(f)


def _policy_sids(subdir: str) -> dict[str, Path]:
    sids: dict[str, Path] = {}
    for path in sorted((TF_DIR / "policies" / subdir).glob("*.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        for statement in doc.get("Statement", []):
            if "Sid" in statement:
                sids[statement["Sid"]] = path
    return sids


class CodeIndex:
    """terraform/ 以下のコードを一度だけ読み込んで、参照を引けるようにする。"""

    CONFIG_RULE_KEY = re.compile(r'"(c\d{2}-[a-z0-9-]+)"\s*=\s*\{')

    def __init__(self) -> None:
        self.scp_sids = _policy_sids("scp")
        self.rcp_sids = _policy_sids("rcp")
        self.tf_files = {
            path: path.read_text(encoding="utf-8")
            for path in sorted(TF_DIR.rglob("*.tf"))
            if ".terraform" not in path.parts
        }
        # Checkov：.checkov.yaml で有効にしている ID と、checkov/ のカスタムポリシーの ID
        config = yaml.safe_load(CHECKOV_CONFIG.read_text(encoding="utf-8")) or {}
        self.checkov_enabled: list[str] = list(config.get("check") or [])
        self.checkov_custom: dict[str, Path] = {}
        for path in sorted(CHECKOV_DIR.glob("*.yaml")):
            policy = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
            self.checkov_custom[policy["metadata"]["id"]] = path

    def _find_literal(self, value: str) -> Path | None:
        needle = f'"{value}"'
        for path, text in self.tf_files.items():
            if needle in text:
                return path
        return None

    def _find_resource(self, address: str) -> Path | None:
        rtype, _, name = address.partition(".")
        pattern = re.compile(rf'resource\s+"{re.escape(rtype)}"\s+"{re.escape(name)}"')
        for path, text in self.tf_files.items():
            if pattern.search(text):
                return path
        return None

    def config_rule_names(self) -> dict[str, Path]:
        """Terraform 内の、統制 ID で始まる Config ルール名（例 c10-restricted-ssh）。"""
        names: dict[str, Path] = {}
        for path, text in self.tf_files.items():
            for name in self.CONFIG_RULE_KEY.findall(text):
                names.setdefault(name, path)
        return names

    def resolve(self, item: object) -> Ref:
        if isinstance(item, str):
            return Ref("text", item)
        if not isinstance(item, dict) or len(item) != 1:
            raise ValueError(f"参照は「種類: 値」の1組で書く: {item!r}")
        ((kind, value),) = item.items()
        value = str(value)
        if kind not in KINDS:
            raise ValueError(f"知らない種類: {kind}")
        if kind == "scp":
            return Ref(kind, value, self.scp_sids.get(value))
        if kind == "rcp":
            return Ref(kind, value, self.rcp_sids.get(value))
        if kind == "terraform":
            return Ref(kind, value, self._find_resource(value))
        if kind in ("config_rule", "securityhub", "ssm_document"):
            return Ref(kind, value, self._find_literal(value))
        if kind == "checkov":
            # 有効にしていなければ「ない」扱い。カスタムならその定義ファイルを指す
            if value not in self.checkov_enabled:
                return Ref(kind, value)
            return Ref(kind, value, self.checkov_custom.get(value, CHECKOV_CONFIG))
        return Ref(kind, value)  # manual


def iter_refs(control: dict, index: CodeIndex):
    """統制の全参照を (欄の名前, Ref) で返す。"""
    for field in IMPL_FIELDS:
        for item in control.get(field) or []:
            yield field, index.resolve(item)
