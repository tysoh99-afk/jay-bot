"""Sample EMA crossover signal; it never submits orders."""

from dataclasses import dataclass
from datetime import datetime

from .broker import Candle


@dataclass(frozen=True)
class Signal:
    direction: str
    candle_time: datetime
    fast_value: float
    slow_value: float


def _ema(values: list[float], period: int) -> list[float]:
    multiplier = 2 / (period + 1)
    result = [values[0]]
    for value in values[1:]:
        result.append((value * multiplier) + (result[-1] * (1 - multiplier)))
    return result


def crossover_signal(
    candles: list[Candle], fast_period: int, slow_period: int
) -> Signal | None:
    if fast_period < 1 or slow_period < 2 or fast_period >= slow_period:
        raise ValueError("Periods must satisfy 1 <= fast_period < slow_period")
    if len(candles) < slow_period + 1:
        raise ValueError(f"At least {slow_period + 1} closed candles are required")

    closes = [candle.close for candle in candles]
    fast = _ema(closes, fast_period)
    slow = _ema(closes, slow_period)
    prior_gap = fast[-2] - slow[-2]
    current_gap = fast[-1] - slow[-1]

    if prior_gap <= 0 < current_gap:
        direction = "BUY"
    elif prior_gap >= 0 > current_gap:
        direction = "SELL"
    else:
        direction = "HOLD"

    return Signal(direction, candles[-1].time, fast[-1], slow[-1])
