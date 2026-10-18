"""Summarize actual closed-position rows exported by GoldFirstBot."""

import argparse
import csv
from collections import defaultdict
from datetime import datetime
import json
from pathlib import Path
from typing import Any


def _parse_time(value: str) -> datetime:
    for pattern in ("%Y.%m.%d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.strptime(value, pattern)
        except ValueError:
            pass
    return datetime.fromisoformat(value)


def load_results(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    seen_positions: set[str] = set()
    with path.open(newline="", encoding="utf-8-sig") as source:
        for row in csv.DictReader(source):
            if not row.get("position_id") or not row.get("net_profit"):
                continue
            position_id = row["position_id"].strip()
            if position_id in seen_positions:
                continue
            seen_positions.add(position_id)
            rows.append(
                {
                    "position_id": position_id,
                    "time": _parse_time(row["time"]),
                    "symbol": row["symbol"].strip(),
                    "direction": row["direction"].strip().upper(),
                    "volume": float(row["volume"]),
                    "net_profit": float(row["net_profit"]),
                    "currency": row.get("currency", ""),
                }
            )
    return sorted(rows, key=lambda row: row["time"])


def _session(hour: int) -> str:
    if hour < 7:
        return "Asia"
    if hour < 13:
        return "London"
    if hour < 21:
        return "New York"
    return "Off hours"


def summarize(rows: list[dict[str, Any]]) -> dict[str, Any]:
    profits = [float(row["net_profit"]) for row in rows]
    wins = [profit for profit in profits if profit > 0]
    losses = [profit for profit in profits if profit < 0]
    cumulative = 0.0
    peak = 0.0
    maximum_drawdown = 0.0
    current_loss_streak = 0
    longest_loss_streak = 0
    for profit in profits:
        cumulative += profit
        peak = max(peak, cumulative)
        maximum_drawdown = max(maximum_drawdown, peak - cumulative)
        current_loss_streak = current_loss_streak + 1 if profit < 0 else 0
        longest_loss_streak = max(longest_loss_streak, current_loss_streak)

    def group_stats(key_fn) -> dict[str, dict[str, Any]]:
        grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for row in rows:
            grouped[key_fn(row)].append(row)
        return {key: _basic_stats(group) for key, group in sorted(grouped.items())}

    return {
        **_basic_stats(rows),
        "average_win": sum(wins) / len(wins) if wins else 0.0,
        "average_loss": sum(losses) / len(losses) if losses else 0.0,
        "maximum_drawdown": maximum_drawdown,
        "longest_losing_streak": longest_loss_streak,
        "by_symbol": group_stats(lambda row: row["symbol"]),
        "by_session": group_stats(lambda row: _session(row["time"].hour)),
        "by_month": group_stats(lambda row: row["time"].strftime("%Y-%m")),
        "sample_warning": "Fewer than 300 closed trades; treat results as preliminary." if len(rows) < 300 else None,
    }


def _basic_stats(rows: list[dict[str, Any]]) -> dict[str, Any]:
    profits = [float(row["net_profit"]) for row in rows]
    wins = [profit for profit in profits if profit > 0]
    losses = [profit for profit in profits if profit < 0]
    gross_profit = sum(wins)
    gross_loss = abs(sum(losses))
    return {
        "trades": len(rows),
        "win_rate_percent": 100.0 * len(wins) / len(rows) if rows else 0.0,
        "net_profit": sum(profits),
        "profit_factor": gross_profit / gross_loss if gross_loss else ("inf" if gross_profit else 0.0),
        "expected_value_per_trade": sum(profits) / len(rows) if rows else 0.0,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_path", type=Path, help="GoldFirstBotResults.csv exported from MT5 Common Files")
    args = parser.parse_args()
    rows = load_results(args.csv_path)
    if not rows:
        parser.error("No closed-position results found in the CSV")
    print(json.dumps(summarize(rows), indent=2, allow_nan=False))


if __name__ == "__main__":
    main()