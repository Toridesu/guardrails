#!/usr/bin/env python3
"""C10 の自動修復にかかった時間を、CloudTrail の記録から測る（中央値と最大値）。

SSH を全世界に開けた記録（AuthorizeSecurityGroupIngress）と、修復用ロールが閉じた記録
（RevokeSecurityGroupIngress）を、セキュリティグループごとに組にして、時刻の差を出す。
デモ4を何回か実行してから使う。CloudTrail のイベント履歴に出るまで、5〜15分ほどかかる。

使い方（リポジトリのルートで）:
  python scripts/measure_remediation.py --profile guardrails-workload --hours 24
  python scripts/measure_remediation.py --events-file events.json   # AWS を呼ばない
    events.json は aws cloudtrail lookup-events の出力（{"Events": [...]}）。2種類を1つにまとめてよい
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

OPEN = "AuthorizeSecurityGroupIngress"
CLOSE = "RevokeSecurityGroupIngress"
WORLD = {"0.0.0.0/0", "::/0"}
SSH_PORT = 22


@dataclass
class Event:
    name: str
    time: datetime
    group_id: str
    actor: str  # userIdentity.arn
    error: str | None
    params: dict


@dataclass
class Result:
    group_id: str
    opened: datetime
    closed: datetime | None  # 閉じられていなければ None

    @property
    def seconds(self) -> float | None:
        return (self.closed - self.opened).total_seconds() if self.closed else None


def parse(raw: dict) -> Event | None:
    """lookup-events の1件を読む。中身（CloudTrailEvent）は JSON の文字列で入っている。"""
    detail = json.loads(raw["CloudTrailEvent"])
    params = detail.get("requestParameters") or {}
    if not params.get("groupId"):
        return None  # グループ名で指定した古い形式は対象外
    return Event(
        name=detail["eventName"],
        time=datetime.fromisoformat(detail["eventTime"].replace("Z", "+00:00")),
        group_id=params["groupId"],
        actor=(detail.get("userIdentity") or {}).get("arn", ""),
        error=detail.get("errorCode"),
        params=params,
    )


def opens_ssh_to_world(params: dict) -> bool:
    """22番（を含む範囲）を、0.0.0.0/0 か ::/0 に開けているか。"""
    for perm in (params.get("ipPermissions") or {}).get("items", []):
        protocol = str(perm.get("ipProtocol"))
        if protocol == "-1":  # すべてのプロトコル・ポート
            pass
        elif protocol in ("tcp", "6"):
            if not perm.get("fromPort", 0) <= SSH_PORT <= perm.get("toPort", 65535):
                continue
        else:
            continue
        cidrs = {r.get("cidrIp") for r in (perm.get("ipRanges") or {}).get("items", [])}
        cidrs |= {r.get("cidrIpv6") for r in (perm.get("ipv6Ranges") or {}).get("items", [])}
        if cidrs & WORLD:
            return True
    return False


def pair(events: list[Event], role_name: str) -> list[Result]:
    """開けた記録ごとに、そのあと修復用ロールが同じグループを閉じた最初の記録を探す。"""
    events = sorted(events, key=lambda e: e.time)
    results = []
    for i, ev in enumerate(events):
        if ev.name != OPEN or ev.error or not opens_ssh_to_world(ev.params):
            continue
        closed = next(
            (
                later.time
                for later in events[i + 1 :]
                if later.name == CLOSE
                and later.group_id == ev.group_id
                and not later.error
                and f":assumed-role/{role_name}/" in later.actor
            ),
            None,
        )
        results.append(Result(ev.group_id, ev.time, closed))
    return results


def lookup(event_name: str, profile: str | None, region: str, hours: float) -> list[dict]:
    start = datetime.now(timezone.utc) - timedelta(hours=hours)
    cmd = [
        "aws", "cloudtrail", "lookup-events",
        "--region", region,
        "--lookup-attributes", f"AttributeKey=EventName,AttributeValue={event_name}",
        "--start-time", start.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "--output", "json",
    ]  # fmt: skip
    if profile:
        cmd += ["--profile", profile]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.exit(f"lookup-events が失敗した:\n{proc.stderr}")
    return json.loads(proc.stdout).get("Events", [])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--profile", help="workload アカウントのプロファイル")
    ap.add_argument("--region", default="ap-northeast-1")
    ap.add_argument("--hours", type=float, default=24, help="何時間前までさかのぼるか（既定 24）")
    ap.add_argument("--role-name", default="guardrails-c10-remediation", help="修復用ロールの名前")
    ap.add_argument("--events-file", type=Path, help="lookup-events の出力を読む（AWS を呼ばない）")
    args = ap.parse_args()

    if args.events_file:
        raw = json.loads(args.events_file.read_text(encoding="utf-8")).get("Events", [])
    else:
        raw = []
        for name in (OPEN, CLOSE):
            raw += lookup(name, args.profile, args.region, args.hours)

    events = [ev for ev in map(parse, raw) if ev]
    results = pair(events, args.role_name)
    if not results:
        print("SSH を全世界に開けた記録が見つからない（デモ4を実行して、5〜15分待ってからもう一度）")
        return 1

    for r in results:
        opened = r.opened.astimezone().strftime("%Y-%m-%d %H:%M:%S")
        if r.closed:
            closed = r.closed.astimezone().strftime("%H:%M:%S")
            print(f"{r.group_id}  開けた {opened}  閉じた {closed}  {r.seconds:5.0f} 秒")
        else:
            print(f"{r.group_id}  開けた {opened}  閉じられていない")

    measured = [r.seconds for r in results if r.seconds is not None]
    unclosed = len(results) - len(measured)
    if measured:
        print(
            f"\n{len(measured)} 回：中央値 {statistics.median(measured):.0f} 秒、"
            f"最大 {max(measured):.0f} 秒"
            + (f"（ほかに閉じられていないものが {unclosed} 件）" if unclosed else "")
        )
    else:
        print(f"\n閉じられたものがない（{unclosed} 件とも開いたまま）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
