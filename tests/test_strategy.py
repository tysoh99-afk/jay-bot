from datetime import datetime, timezone, timedelta

import pytest

from jaytrade.broker import Candle
from jaytrade.strategy import crossover_signal


def make_candles(closes: list[float]) -> list[Candle]:
    start = datetime(2026, 1, 1, tzinfo=timezone.utc)
    return [
        Candle(start + timedelta(minutes=index), close)
        for index, close in enumerate(closes)
    ]


def test_signal_waits_for_enough_closed_candles() -> None:
    with pytest.raises(ValueError, match="closed candles"):
        crossover_signal(make_candles([1.0, 1.1, 1.2]), 2, 3)


def test_crossover_signal_is_hold_when_no_cross_occurs() -> None:
    candles = make_candles([1.0 + index * 0.01 for index in range(10)])

    signal = crossover_signal(candles, 2, 4)

    assert signal is not None
    assert signal.direction == "HOLD"
