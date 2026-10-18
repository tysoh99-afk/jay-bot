"""Small read-only adapter around the MetaTrader 5 Python package."""

import logging
import math
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from .config import TIMEFRAMES


@dataclass(frozen=True)
class Candle:
    time: datetime
    close: float


@dataclass(frozen=True)
class Quote:
    bid: float
    ask: float
    time: datetime


class Mt5Client:
    def __init__(self, terminal_path: str | None = None) -> None:
        try:
            import MetaTrader5 as mt5
        except ImportError as error:
            raise RuntimeError(
                "MetaTrader5 is not installed. Install dependencies with "
                "'python -m pip install -r requirements.txt'."
            ) from error
        self._mt5: Any = mt5
        self._terminal_path = terminal_path

    def connect(self) -> None:
        logging.info("Attempting MT5 connection with terminal_path=%s", self._terminal_path)
        initialized = (
            self._mt5.initialize(self._terminal_path)
            if self._terminal_path
            else self._mt5.initialize()
        )
        logging.info("MT5 initialize() returned %s", initialized)
        if not initialized:
            error = self._mt5.last_error()
            logging.error("MT5 initialize failed: %s", error)
            raise ConnectionError(
                f"Could not connect to MetaTrader 5: {error}. "
                "Open MT5, sign in to the FXPesa account, and try again."
            )
        account = self._mt5.account_info()
        logging.info("MT5 account_info() = %s", account)
        if account is None:
            error = self._mt5.last_error()
            logging.error("MT5 account info missing after initialize: %s", error)
            self.close()
            raise ConnectionError(f"MT5 is open but no account is available: {error}")

        terminal = self._mt5.terminal_info()
        logging.info("MT5 terminal_info() = %s", terminal)
        if terminal is None or not getattr(terminal, "connected", False):
            error = self._mt5.last_error()
            self.close()
            raise ConnectionError(f"MetaTrader 5 is open but not connected to the broker: {error}")

    def close(self) -> None:
        self._mt5.shutdown()

    def status(self) -> tuple[str, str]:
        terminal = self._mt5.terminal_info()
        account = self._mt5.account_info()
        logging.info("status() terminal=%s account=%s", terminal, account)
        if terminal is None or account is None:
            last_error = self._mt5.last_error()
            logging.error("Could not read MT5 status: %s", last_error)
            raise ConnectionError(f"Could not read MT5 status: {last_error}")
        return str(account.server), str(account.currency)

    def is_demo_account(self) -> bool:
        account = self._mt5.account_info()
        demo_mode = getattr(self._mt5, "ACCOUNT_TRADE_MODE_DEMO", None)
        return account is not None and demo_mode is not None and getattr(account, "trade_mode", None) == demo_mode

    def is_connected(self) -> bool:
        terminal = self._mt5.terminal_info()
        return terminal is not None and bool(getattr(terminal, "connected", False))

    def positions(self) -> list[Any]:
        positions = self._mt5.positions_get()
        if positions is None:
            raise RuntimeError(f"Could not read MT5 open positions: {self._mt5.last_error()}")
        return list(positions)

    def quote(self, symbol: str) -> Quote:
        self._select_symbol(symbol)
        tick = self._mt5.symbol_info_tick(symbol)
        if tick is None:
            raise RuntimeError(f"No current tick for {symbol}: {self._mt5.last_error()}")
        return Quote(
            bid=float(tick.bid),
            ask=float(tick.ask),
            time=datetime.fromtimestamp(tick.time, timezone.utc),
        )

    def candles(self, symbol: str, timeframe: str, count: int) -> list[Candle]:
        self._select_symbol(symbol)
        mt5_timeframe = getattr(self._mt5, TIMEFRAMES[timeframe])
        rates = self._mt5.copy_rates_from_pos(symbol, mt5_timeframe, 1, count)
        if rates is None or len(rates) == 0:
            raise RuntimeError(f"No candle data for {symbol}: {self._mt5.last_error()}")
        return [
            Candle(
                time=datetime.fromtimestamp(int(rate["time"]), timezone.utc),
                close=float(rate["close"]),
            )
            for rate in rates
        ]

    def market_order(
        self,
        symbol: str,
        direction: str,
        lots: float = 0.01,
        comment: str = "jaytrade",
        take_profit: float | None = None,
        stop_loss: float | None = None,
        take_profit_usd: float | None = None,
        stop_loss_usd: float | None = None,
    ) -> Any:
        side = direction.upper()
        if side not in {"BUY", "SELL"}:
            raise ValueError("direction must be BUY or SELL")
        if lots <= 0:
            raise ValueError("lots must be positive")

        self._select_symbol(symbol)
        tick = self._mt5.symbol_info_tick(symbol)
        if tick is None:
            raise RuntimeError(f"No current tick for {symbol}: {self._mt5.last_error()}")

        request = {
            "action": self._mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": float(lots),
            "type": self._mt5.ORDER_TYPE_BUY if side == "BUY" else self._mt5.ORDER_TYPE_SELL,
            "price": float(tick.ask) if side == "BUY" else float(tick.bid),
            "deviation": 10,
            "magic": 0,
            "comment": comment,
            "type_filling": self._mt5.ORDER_FILLING_IOC,
            "type_time": self._mt5.ORDER_TIME_GTC,
        }
        if take_profit_usd is not None:
            if take_profit is not None:
                raise ValueError("Specify take_profit or take_profit_usd, not both")
            take_profit = self._price_for_profit(
                symbol,
                side,
                lots,
                request["price"],
                float(take_profit_usd),
            )
        if stop_loss_usd is not None:
            if stop_loss is not None:
                raise ValueError("Specify stop_loss or stop_loss_usd, not both")
            stop_loss = self._price_for_profit(
                symbol,
                side,
                lots,
                request["price"],
                -abs(float(stop_loss_usd)),
            )
        if take_profit is not None:
            request["tp"] = float(take_profit)
        if stop_loss is not None:
            request["sl"] = float(stop_loss)
        logging.info("Submitting MT5 market order: %s", request)
        result = self._mt5.order_send(request)
        done = getattr(self._mt5, "TRADE_RETCODE_DONE", getattr(result, "retcode", None))
        if getattr(result, "retcode", None) != done:
            raise RuntimeError(
                f"MT5 trade rejected for {symbol}: retcode={getattr(result, 'retcode', None)}, "
                f"comment={getattr(result, 'comment', '')}"
            )
        logging.info(
            "Executed %s %s lots on %s at price=%s ticket=%s",
            side,
            lots,
            symbol,
            request["price"],
            getattr(result, "order", "unknown"),
        )
        return result

    def set_position_protection(
        self,
        ticket: int,
        take_profit_usd: float,
        stop_loss_usd: float,
    ) -> Any | None:
        positions = self._mt5.positions_get(ticket=int(ticket))
        if positions is None:
            raise RuntimeError(f"Could not find MT5 position {ticket}: {self._mt5.last_error()}")
        if not positions:
            return None

        position = positions[0]
        side = "BUY" if position.type == self._mt5.POSITION_TYPE_BUY else "SELL"
        take_profit = self._price_for_profit(
            str(position.symbol), side, float(position.volume), float(position.price_open), abs(take_profit_usd)
        )
        stop_loss = self._price_for_profit(
            str(position.symbol), side, float(position.volume), float(position.price_open), -abs(stop_loss_usd)
        )
        symbol_info = self._mt5.symbol_info(str(position.symbol))
        tick_size = float(getattr(symbol_info, "trade_tick_size", 0.0) or symbol_info.point)
        if abs(float(position.tp) - take_profit) < tick_size / 2 and abs(float(position.sl) - stop_loss) < tick_size / 2:
            return None
        request = {
            "action": self._mt5.TRADE_ACTION_SLTP,
            "symbol": str(position.symbol),
            "position": int(position.ticket),
            "tp": take_profit,
            "sl": stop_loss,
        }
        logging.info("Setting MT5 position protection: %s", request)
        result = self._mt5.order_send(request)
        done = getattr(self._mt5, "TRADE_RETCODE_DONE", getattr(result, "retcode", None))
        if getattr(result, "retcode", None) != done:
            raise RuntimeError(
                f"MT5 protection rejected for position {ticket}: retcode={getattr(result, 'retcode', None)}, "
                f"comment={getattr(result, 'comment', '')}"
            )
        return result

    def _price_for_profit(
        self,
        symbol: str,
        direction: str,
        lots: float,
        entry_price: float,
        target_profit: float,
    ) -> float:
        if target_profit == 0:
            return entry_price
        self._select_symbol(symbol)
        symbol_info = self._mt5.symbol_info(symbol)
        if symbol_info is None:
            raise RuntimeError(f"Could not read symbol details for {symbol}: {self._mt5.last_error()}")

        side = direction.upper()
        order_type = self._mt5.ORDER_TYPE_BUY if side == "BUY" else self._mt5.ORDER_TYPE_SELL
        price_direction = 1 if ((side == "BUY") == (target_profit > 0)) else -1
        digits = int(symbol_info.digits)
        point = float(symbol_info.point)
        tick_size = float(getattr(symbol_info, "trade_tick_size", 0.0) or point)
        tolerance = max(1e-6, abs(target_profit) * 1e-10)

        def profit_at(price: float) -> float:
            result = self._mt5.order_calc_profit(order_type, symbol, lots, entry_price, price)
            if result is None:
                raise RuntimeError(f"Could not calculate P/L for {symbol}: {self._mt5.last_error()}")
            return float(result)

        def reached(price: float) -> bool:
            profit = profit_at(price)
            return profit >= target_profit - tolerance if target_profit > 0 else profit <= target_profit + tolerance

        step = max(tick_size, abs(entry_price) * 1e-6)
        inside_price = entry_price
        outside_price: float | None = None
        for _ in range(40):
            candidate = round(entry_price + price_direction * step, digits)
            if candidate <= 0:
                raise RuntimeError(f"Could not find a valid protection price for {symbol}")
            if reached(candidate):
                outside_price = candidate
                break
            step *= 2
        if outside_price is None:
            raise RuntimeError(f"Could not find a price for the {target_profit:.2f} USD threshold on {symbol}")

        for _ in range(48):
            midpoint = round((inside_price + outside_price) / 2, digits)
            if midpoint in {inside_price, outside_price}:
                break
            if reached(midpoint):
                outside_price = midpoint
            else:
                inside_price = midpoint

        ticks = outside_price / tick_size
        rounded_price = (
            math.ceil(ticks - 1e-10) if price_direction > 0 else math.floor(ticks + 1e-10)
        ) * tick_size
        minimum_distance = float(getattr(symbol_info, "trade_stops_level", 0)) * point
        if abs(rounded_price - entry_price) < minimum_distance:
            raise RuntimeError(
                f"The broker's minimum stop distance for {symbol} is wider than the requested "
                f"{abs(target_profit):.2f} USD threshold"
            )

        rounded_price = round(rounded_price, digits)
        while not reached(rounded_price):
            rounded_price = round(rounded_price + price_direction * tick_size, digits)
        return rounded_price

    def close_position(self, ticket: int) -> Any | None:
        positions = self._mt5.positions_get(ticket=int(ticket))
        if positions is None:
            raise RuntimeError(f"Could not find MT5 position {ticket}: {self._mt5.last_error()}")
        if not positions:
            logging.info("Position %s is already closed", ticket)
            return None

        position = positions[0]
        symbol = str(position.symbol)
        self._select_symbol(symbol)
        tick = self._mt5.symbol_info_tick(symbol)
        if tick is None:
            raise RuntimeError(f"No current tick for {symbol}: {self._mt5.last_error()}")

        is_buy = position.type == self._mt5.POSITION_TYPE_BUY
        request = {
            "action": self._mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "position": int(position.ticket),
            "volume": float(position.volume),
            "type": self._mt5.ORDER_TYPE_SELL if is_buy else self._mt5.ORDER_TYPE_BUY,
            "price": float(tick.bid) if is_buy else float(tick.ask),
            "deviation": 10,
            "magic": 0,
            "comment": "jaytrade-minute-exit",
            "type_filling": self._mt5.ORDER_FILLING_IOC,
            "type_time": self._mt5.ORDER_TIME_GTC,
        }
        logging.info("Closing timed MT5 position: %s", request)
        result = self._mt5.order_send(request)
        done = getattr(self._mt5, "TRADE_RETCODE_DONE", getattr(result, "retcode", None))
        if getattr(result, "retcode", None) != done:
            raise RuntimeError(
                f"MT5 close rejected for position {ticket}: retcode={getattr(result, 'retcode', None)}, "
                f"comment={getattr(result, 'comment', '')}"
            )
        logging.info("Closed MT5 position %s", ticket)
        return result

    def _select_symbol(self, symbol: str) -> None:
        if not self._mt5.symbol_select(symbol, True):
            raise RuntimeError(
                f"Could not select symbol {symbol} in MT5 Market Watch: "
                f"{self._mt5.last_error()}. Check the broker's exact symbol name."
            )
