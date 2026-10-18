"""Run the MT5 read-only signal monitor."""

import argparse
import logging
import time

from .broker import Mt5Client
from .config import Settings
from .strategy import crossover_signal


def main() -> int:
    parser = argparse.ArgumentParser(description="FXPesa MT5 read-only signal monitor")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="check connection and data once")
    mode.add_argument("--watch", action="store_true", help="monitor closed candles")
    arguments = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    settings = Settings.from_environment()
    client = Mt5Client(settings.terminal_path)
    try:
        client.connect()
        server, currency = client.status()
        logging.info("Connected to MT5 server %s (account currency %s)", server, currency)

        logging.info("Watching %s on %s; Python mode is read-only", settings.symbol, settings.timeframe)

        previous_candle = None
        while True:
            quote = client.quote(settings.symbol)
            candles = client.candles(
                settings.symbol,
                settings.timeframe,
                settings.slow_ema + 2,
            )
            signal = crossover_signal(candles, settings.fast_ema, settings.slow_ema)
            logging.info(
                "MARKET %s bid=%s ask=%s",
                settings.symbol,
                quote.bid,
                quote.ask,
            )
            if signal is not None and signal.candle_time != previous_candle:
                logging.info(
                    "Closed candle %s: %s (EMA%d=%.5f EMA%d=%.5f)",
                    signal.candle_time.isoformat(),
                    signal.direction,
                    settings.fast_ema,
                    signal.fast_value,
                    settings.slow_ema,
                    signal.slow_value,
                )
                previous_candle = signal.candle_time
            if arguments.check:
                return 0
            time.sleep(settings.poll_seconds)
    except KeyboardInterrupt:
        logging.info("Stopped")
        return 0
    except (ConnectionError, RuntimeError, ValueError) as error:
        logging.error("%s", error)
        return 1
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
