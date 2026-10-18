# Gold-First MT5 Bot

This existing project contains a native MT5 Expert Advisor for XAUUSD-first, then EURUSD and enabled additional symbols. The MQL5 EA owns strategy decisions, order sizing, protective stops, and all automated execution. Python is a read-only local API/dashboard bridge; it has no random-entry loop or order endpoint.

## Current State

- Complete: M15/H1 trend-pullback strategy, gold TP 10.0 and SL 3.0 price units, 0.5% default equity risk, five managed open positions maximum, one per symbol, daily trade limit default 20/configurable to 25, daily-loss protection, and demo-account-only EA initialization.
- Complete: MT5 chart START/STOP controls, status lamp, risk/settings controls, and position management that continues after STOP with broker SL/TP left in place.
- Complete: local API and `index.html` dashboard using a file bridge. The EA writes live status and actual per-symbol checks to MT5 Common Files. If the EA is not attached, the API reports EA NOT ATTACHED while a cached read-only MT5 probe can still show current quote tags; if MT5 itself is unavailable it reports DISCONNECTED. EA heartbeats older than 10 seconds are DATA STALE.
- Complete: Python unit/API tests and MetaEditor compilation of the workspace EA source; details are recorded in `TODO.md`.
- Not complete: no Strategy Tester run, broker-confirmed demo forward test, or live EA heartbeat has been recorded in this environment. No performance result is claimed.

## Requirements and Install

Use Windows, MT5/MetaEditor, and Python 3.10+ supported by the installed MetaTrader5 Python package. Keep broker credentials in MT5; neither the API nor dashboard reads or displays passwords or account login identifiers.

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -e ".[test]"
Copy-Item .env.example .env
```

Put your OpenAI API key in the project-root `.env` as `OPENAI_API_KEY=...`; do not put it in `.env.example` or commit it. An API key does not include API credits: enable API billing and check usage limits in the OpenAI Platform. ChatGPT subscriptions and API billing are separate.

The `.env` values for `MT5_SYMBOL` and `MT5_TIMEFRAME` are used by the separate read-only Python market inspector. The native EA has its own M15/H1 inputs and enabled-symbol settings. Set `MT5_TERMINAL_PATH` only if MT5 is not found by the installed MetaTrader5 package.

## Strategy and Risk Defaults

- Symbol priority: XAUUSD, EURUSD, then configured extras (`GBPUSD,USDJPY` by default); broker suffixes are resolved from Market Watch.
- Entry: completed-candle EMA 20/50/200 alignment, H1 EMA 200 direction, RSI, ADX, EMA pullback, bullish/bearish candle confirmation, spread/ATR limits, target clearance, and minimum setup score.
- Gold exits: TP 10.0 and SL 3.0 absolute price units; FX exits use ATR multiples unless the configured exit mode changes.
- Maximum 5 EA-managed positions total; one per symbol. Daily entries default to 20 and can be set from 1 to 50.
- Default risk is 0.5% of equity per trade; total open risk is limited to 2%, gold-specific open risk to 1%, and daily equity loss protection defaults to 2%.
- Break-even, trailing, and time exit are optional inputs. Live FXStreet and CNBC RSS headlines are shown as advisory context only; they do not change EA entries. AI-assisted headline analysis uses the configured `OPENAI_API_KEY`.
- No martingale or grid-entry logic is used.

Position sizing uses MT5 `OrderCalcProfit` and broker contract parameters. Trades are submitted with broker-side SL/TP. Status changes to TRADE EXECUTED only after an entry deal is received; a placed-but-unfilled order remains TRADE REQUEST SUBMITTED.

## Compile and Attach in MT5

The checked-in files are under `MQL5/Experts` and `MQL5/Include`. Preserve this layout when copying them into the terminal data folder: `GoldFirstBot.mq5` belongs in `MQL5/Experts`, and both `.mqh` files in `MQL5/Include`. The EA uses relative includes to those project files.

Open `GoldFirstBot.mq5` in MetaEditor and compile. A command-line compile can be run from PowerShell:

```powershell
& "C:\Program Files\MetaTrader 5\MetaEditor64.exe" '/compile:"C:\path\to\MQL5\Experts\GoldFirstBot.mq5"' /log
```

Read `GoldFirstBot.log` beside the source and require `0 errors`. In MT5, sign in to a demo account, make the exact symbols visible in Market Watch, enable algorithmic trading, refresh Navigator, and attach `GoldFirstBot` to a chart. The EA refuses non-demo accounts. Press START in its panel to allow entries. STOP disables new entries while its timer continues managing existing positions and broker SL/TP remain attached.

The EA chart provides START, STOP, auto-start, symbol toggles, settings, position/risk metrics, a colored status light, and a two-click confirmed close-all-EA-positions action. Default auto-start is off. The persistent daily counters and protection state use MT5 terminal global variables/history.

## Live Dashboard Bridge

The EA writes `GoldFirstBotStatus.json` and reads `GoldFirstBot.command` in the MT5 Common Files directory, normally `%APPDATA%\MetaQuotes\Terminal\Common\Files`. Closed EA trades are appended to `GoldFirstBotResults.csv` in the same directory. The JSON includes the EA state, freshness epoch, enabled symbols, actual per-symbol strategy checks, safety blocks, equity, limits, spread, and last trade. It excludes credentials and account identifiers.

Run the local API while MT5 and the EA are running:

```powershell
uvicorn app:app --host 127.0.0.1 --port 5000
```

Open <http://127.0.0.1:5000/> in this workspace. Do not open `index.html` directly with `file://`: the page uses the same-origin API at `/api/status` and `/api/control`. The API reads `MT5_COMMON_FILES_DIR` if set; otherwise it uses the standard Common Files folder. Manual START/STOP actions are queued only while MT5 is connected; Python does not execute trades. If the EA is unattached, the requested action remains visibly pending and is consumed when the EA next runs. Actual RUNNING/STOPPED state changes only after the EA acknowledges the command. A queued START is a manual request to allow new entries once the EA is attached, so use it only when intended. Polling stops showing RUNNING when the feed disconnects or becomes stale.

The status display separates satisfied, remaining, blocked, and not-evaluated conditions. Optional checks such as higher-timeframe alignment are labeled not applicable when disabled. A global risk block is shown as BLOCKED and is not counted as a valid entry opportunity. When the EA is unattached, the market-tag panel shows current bid/ask/spread plus a clearly labeled read-only EMA 9/21 sample; it is not the EA signal or a trade recommendation. Closed-trade history comes from EA result records, not sample or fabricated values.

The live-news panel reads the public FXStreet and CNBC RSS feeds, caches responses briefly, labels direct gold coverage separately from broader market drivers, and shows feed freshness and failures. Topic labels are keyword-based context, not sentiment or price-impact forecasts. News analysis is an optional OpenAI summary and is never sent to the EA or used to open, modify, or close positions. Feed availability depends on the publisher and network; stale or unavailable news is labeled in the UI.

## Python Read-Only Tools

```powershell
python -m jaytrade --check
python -m jaytrade --watch
```

These inspect quotes and a sample EMA crossover only; they do not implement the native strategy or send orders. The `/market` API is also read-only. TradingView webhook support is an optional analysis feature and is not connected to EA entry decisions.

## Tests and Strategy Tester

Run Python tests with:

```powershell
python -m pytest
```

The API tests use temporary status/command files and verify DISCONNECTED, DATA STALE, WAITING FOR ENTRY, counter/safety reporting, command queuing, and that the Python trade route is disabled. They do not substitute for a live MT5 bridge or broker test.

For MT5 Strategy Tester, select `GoldFirstBot`, **Every tick based on real ticks**, the broker's demo symbol specification, commission/swap, and M15 data. Test XAUUSD and EURUSD individually, then verify additional-symbol scanning and multi-symbol limits. Check chart status, daily counters, risk halts, stop placement, and STOP behavior. A chart visual test and a Strategy Tester report have not been run yet.

For CSV analysis:

```powershell
python Python\analyze_backtest.py path\to\GoldFirstBotResults.csv
```

Use separate training, validation, and out-of-sample periods, then demo forward-test with small risk. Do not infer profitability from compilation or unit tests. See `TODO.md` for the remaining verification steps.