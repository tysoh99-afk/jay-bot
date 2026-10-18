"""Environment-backed settings for the MT5 signal monitor."""

from dataclasses import dataclass
import os
from pathlib import Path

from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parents[2]
load_dotenv(PROJECT_ROOT / ".env")


TIMEFRAMES = {
    "M1": "TIMEFRAME_M1",
    "M5": "TIMEFRAME_M5",
    "M15": "TIMEFRAME_M15",
    "M30": "TIMEFRAME_M30",
    "H1": "TIMEFRAME_H1",
    "H4": "TIMEFRAME_H4",
    "D1": "TIMEFRAME_D1",
}


@dataclass(frozen=True)
class Settings:
    symbol: str = "EURUSD"
    timeframe: str = "M5"
    fast_ema: int = 9
    slow_ema: int = 21
    poll_seconds: int = 5
    terminal_path: str | None = None

    @classmethod
    def from_environment(cls) -> "Settings":
        settings = cls(
            symbol=os.getenv("MT5_SYMBOL", "EURUSD").strip(),
            timeframe=os.getenv("MT5_TIMEFRAME", "M5").upper().strip(),
            fast_ema=int(os.getenv("FAST_EMA", "9")),
            slow_ema=int(os.getenv("SLOW_EMA", "21")),
            poll_seconds=int(os.getenv("POLL_SECONDS", "5")),
            terminal_path=os.getenv("MT5_TERMINAL_PATH", "").strip() or None,
        )
        settings.validate()
        return settings

    def validate(self) -> None:
        if not self.symbol:
            raise ValueError("MT5_SYMBOL must not be empty")
        if self.timeframe not in TIMEFRAMES:
            raise ValueError(f"Unsupported timeframe: {self.timeframe}")
        if self.fast_ema < 1 or self.slow_ema < 2:
            raise ValueError("EMA periods must be positive; SLOW_EMA must be at least 2")
        if self.fast_ema >= self.slow_ema:
            raise ValueError("FAST_EMA must be smaller than SLOW_EMA")
        if self.poll_seconds < 1:
            raise ValueError("POLL_SECONDS must be at least 1")
