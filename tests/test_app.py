import json
import time
from types import SimpleNamespace

from fastapi.testclient import TestClient

import app as app_module
from app import app, recent_alerts
from src.jaytrade.broker import Mt5Client


client = TestClient(app)


def test_market_order_builds_mt5_request() -> None:
    fake_mt5 = SimpleNamespace(
        ORDER_TYPE_BUY=0,
        ORDER_TYPE_SELL=1,
        ORDER_FILLING_IOC=2,
        ORDER_TIME_GTC=0,
        TRADE_ACTION_DEAL=1,
        symbol_select=lambda symbol, value: True,
        symbol_info_tick=lambda symbol: SimpleNamespace(bid=1.1, ask=1.11),
        order_send=lambda request: SimpleNamespace(retcode=10009, comment="OK", order=42, price=request["price"]),
    )
    client_obj = Mt5Client.__new__(Mt5Client)
    client_obj._mt5 = fake_mt5

    result = client_obj.market_order("EURUSD", "BUY", lots=0.01, take_profit=1.12, stop_loss=1.10)

    assert result.order == 42
    assert result.price == 1.11


def test_recent_trade_history_reads_mt5_utf16_csv(monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("MT5_COMMON_FILES_DIR", str(tmp_path))
    (tmp_path / "GoldFirstBotResults.csv").write_text(
        "time,position_id,symbol,direction,volume,net_profit,currency\n"
        "2026.10.16 10:00:00,123,XAUUSD,BUY,0.10,12.50,USD\n",
        encoding="utf-16",
    )

    history = app_module._recent_trade_history()

    assert history == [{
        "time": "2026.10.16 10:00:00",
        "symbol": "XAUUSD",
        "direction": "BUY",
        "net_profit": "12.50",
        "currency": "USD",
    }]


def test_market_order_converts_usd_targets_to_mt5_prices() -> None:
    captured = {}

    def calc_profit(order_type, symbol, volume, open_price, close_price):
        direction = 1 if order_type == 0 else -1
        return direction * (close_price - open_price) * 1000 * volume

    fake_mt5 = SimpleNamespace(
        ORDER_TYPE_BUY=0,
        ORDER_TYPE_SELL=1,
        ORDER_FILLING_IOC=2,
        ORDER_TIME_GTC=0,
        TRADE_ACTION_DEAL=1,
        TRADE_RETCODE_DONE=10009,
        symbol_select=lambda symbol, value: True,
        symbol_info_tick=lambda symbol: SimpleNamespace(bid=100.0, ask=100.0),
        symbol_info=lambda symbol: SimpleNamespace(digits=2, point=0.01, trade_tick_size=0.01, trade_stops_level=0),
        order_calc_profit=calc_profit,
        order_send=lambda request: (captured.update(request=request) or SimpleNamespace(retcode=10009, order=43)),
    )
    client_obj = Mt5Client.__new__(Mt5Client)
    client_obj._mt5 = fake_mt5

    client_obj.market_order("XAUUSD", "BUY", 0.01, take_profit_usd=10.0, stop_loss_usd=2.0)

    assert captured["request"]["tp"] == 101.0
    assert captured["request"]["sl"] == 99.8


def test_existing_position_can_be_protected_with_usd_targets() -> None:
    captured = {}

    def calc_profit(order_type, symbol, volume, open_price, close_price):
        direction = 1 if order_type == 0 else -1
        return direction * (close_price - open_price) * 1000 * volume

    fake_mt5 = SimpleNamespace(
        POSITION_TYPE_BUY=0,
        ORDER_TYPE_BUY=0,
        ORDER_TYPE_SELL=1,
        TRADE_ACTION_SLTP=6,
        TRADE_RETCODE_DONE=10009,
        symbol_select=lambda symbol, value: True,
        symbol_info=lambda symbol: SimpleNamespace(digits=2, point=0.01, trade_tick_size=0.01, trade_stops_level=0),
        order_calc_profit=calc_profit,
        positions_get=lambda **kwargs: [SimpleNamespace(ticket=42, symbol="XAUUSD", type=0, volume=0.01, price_open=100.0, sl=0.0, tp=0.0)],
        order_send=lambda request: (captured.update(request=request) or SimpleNamespace(retcode=10009)),
    )
    client_obj = Mt5Client.__new__(Mt5Client)
    client_obj._mt5 = fake_mt5

    client_obj.set_position_protection(42, 10.0, 2.0)

    assert captured["request"]["position"] == 42
    assert captured["request"]["tp"] == 101.0
    assert captured["request"]["sl"] == 99.8


def test_sell_position_protection_maps_profit_target_and_stop_correctly() -> None:
    captured = {}

    def calc_profit(order_type, symbol, volume, open_price, close_price):
        direction = 1 if order_type == 0 else -1
        return direction * (close_price - open_price) * 1000 * volume

    fake_mt5 = SimpleNamespace(
        POSITION_TYPE_BUY=0,
        ORDER_TYPE_BUY=0,
        ORDER_TYPE_SELL=1,
        TRADE_ACTION_SLTP=6,
        TRADE_RETCODE_DONE=10009,
        symbol_select=lambda symbol, value: True,
        symbol_info=lambda symbol: SimpleNamespace(digits=2, point=0.01, trade_tick_size=0.01, trade_stops_level=0),
        order_calc_profit=calc_profit,
        positions_get=lambda **kwargs: [SimpleNamespace(ticket=43, symbol="XAUUSD", type=1, volume=0.01, price_open=100.0, sl=0.0, tp=0.0)],
        order_send=lambda request: (captured.update(request=request) or SimpleNamespace(retcode=10009)),
    )
    client_obj = Mt5Client.__new__(Mt5Client)
    client_obj._mt5 = fake_mt5

    client_obj.set_position_protection(43, 10.0, 3.0)

    assert captured["request"]["tp"] == 99.0
    assert captured["request"]["sl"] == 100.3


def test_demo_account_check_requires_mt5_demo_mode() -> None:
    fake_mt5 = SimpleNamespace(
        ACCOUNT_TRADE_MODE_DEMO=0,
        account_info=lambda: SimpleNamespace(trade_mode=0),
    )
    client_obj = Mt5Client.__new__(Mt5Client)
    client_obj._mt5 = fake_mt5

    assert client_obj.is_demo_account() is True

    fake_mt5.account_info = lambda: SimpleNamespace(trade_mode=2)
    assert client_obj.is_demo_account() is False


def test_connect_rejects_disconnected_mt5_terminal() -> None:
    fake_mt5 = SimpleNamespace(
        initialize=lambda: True,
        account_info=lambda: SimpleNamespace(login=1),
        terminal_info=lambda: SimpleNamespace(connected=False),
        last_error=lambda: (1, "No connection"),
        shutdown=lambda: None,
    )
    client_obj = Mt5Client.__new__(Mt5Client)
    client_obj._mt5 = fake_mt5
    client_obj._terminal_path = None

    try:
        client_obj.connect()
    except ConnectionError as error:
        assert "not connected" in str(error)
    else:
        raise AssertionError("A locally initialized but disconnected MT5 terminal must be rejected")


def test_timed_position_close_sends_opposite_market_order() -> None:
    captured = {}
    fake_mt5 = SimpleNamespace(
        POSITION_TYPE_BUY=0,
        ORDER_TYPE_BUY=0,
        ORDER_TYPE_SELL=1,
        ORDER_FILLING_IOC=2,
        ORDER_TIME_GTC=0,
        TRADE_ACTION_DEAL=1,
        TRADE_RETCODE_DONE=10009,
        symbol_select=lambda symbol, value: True,
        symbol_info_tick=lambda symbol: SimpleNamespace(bid=1.1, ask=1.11),
        positions_get=lambda **kwargs: [SimpleNamespace(ticket=42, symbol="EURUSD", volume=0.01, type=0)],
        order_send=lambda request: (captured.update(request=request) or SimpleNamespace(retcode=10009)),
    )
    client_obj = Mt5Client.__new__(Mt5Client)
    client_obj._mt5 = fake_mt5

    client_obj.close_position(42)

    assert captured["request"]["position"] == 42
    assert captured["request"]["type"] == fake_mt5.ORDER_TYPE_SELL
    assert captured["request"]["price"] == 1.1


def _write_ea_snapshot(directory, **changes) -> None:
    snapshot = {
        "updated_epoch": time.time(),
        "running": True,
        "connected": True,
        "status": "RUNNING - WAITING FOR ENTRY",
        "daily_trades": 18,
        "daily_limit": 20,
        "positions": 2,
        "max_positions": 5,
        "safety_block": "",
        "symbols": [{"symbol": "XAUUSD", "checks": [{"name": "RSI confirmation", "passed": False}]}],
    }
    snapshot.update(changes)
    (directory / "GoldFirstBotStatus.json").write_text(json.dumps(snapshot), encoding="utf-8")


def test_status_without_ea_heartbeat_is_disconnected(monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("MT5_COMMON_FILES_DIR", str(tmp_path))
    market_tags = [{"symbol": "XAUUSD", "bid": 4100.0, "ask": 4100.2, "spread": 0.2, "sample_signal": "HOLD"}]
    monkeypatch.setattr(
        app_module,
        "_read_market_tags",
        lambda: {"connected": True, "tags": market_tags, "error": ""},
    )

    response = client.get("/api/status")

    assert response.status_code == 200
    assert response.json()["bot_status"] == "EA NOT ATTACHED"
    assert response.json()["data_state"] == "EA NOT ATTACHED"
    assert response.json()["mt5_connected"] is True
    assert response.json()["market_tags"] == market_tags


def test_missing_market_connection_stays_disconnected(monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("MT5_COMMON_FILES_DIR", str(tmp_path))
    monkeypatch.setattr(
        app_module,
        "_read_market_tags",
        lambda: {"connected": False, "tags": [], "error": "MT5 terminal is not connected"},
    )

    status = client.get("/api/status").json()

    assert status["bot_status"] == "DISCONNECTED"
    assert status["mt5_connected"] is False


def test_status_handles_mt5_client_initialization_failure(monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("MT5_COMMON_FILES_DIR", str(tmp_path))
    app_module._market_tag_cache.update(fetched_epoch=0.0, connected=False, tags=[])

    def fail_to_initialize(*args) -> None:
        raise RuntimeError("MetaTrader5 is not installed")

    monkeypatch.setattr(app_module, "Mt5Client", fail_to_initialize)

    response = client.get("/api/status")

    assert response.status_code == 200
    assert response.json()["bot_status"] == "DISCONNECTED"
    assert response.json()["warnings"] == ["MetaTrader5 is not installed"]


def test_hosted_status_waits_for_ea_heartbeat_without_local_mt5(monkeypatch) -> None:
    monkeypatch.setenv("MT5_BRIDGE_TOKEN", "bridge-secret")
    monkeypatch.setenv("DASHBOARD_ACCESS_TOKEN", "dashboard-secret")
    monkeypatch.setattr(app_module, "_remote_snapshot", None)
    monkeypatch.setattr(app_module, "_read_market_tags", lambda: (_ for _ in ()).throw(AssertionError()))

    response = client.get("/api/status", headers={"Authorization": "Bearer dashboard-secret"})

    assert response.status_code == 200
    assert response.json()["error"] == "Waiting for the MT5 EA cloud heartbeat"
    assert "Attach GoldFirstBot" in response.json()["warnings"][0]


def test_status_marks_old_heartbeat_stale(monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("MT5_COMMON_FILES_DIR", str(tmp_path))
    _write_ea_snapshot(tmp_path, updated_epoch=time.time() - 30)

    status = client.get("/api/status").json()

    assert status["bot_status"] == "DATA STALE"
    assert status["data_state"] == "DATA STALE"


def test_status_reports_waiting_checklist_daily_counters_and_protection(monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("MT5_COMMON_FILES_DIR", str(tmp_path))
    _write_ea_snapshot(tmp_path, safety_block="Daily loss protection active")

    status = client.get("/api/status").json()

    assert status["bot_status"] == "WAITING FOR ENTRY"
    assert status["trades_remaining"] == 2
    assert status["symbols"][0]["checks"][0]["passed"] is False
    assert "Daily loss protection active" in status["warnings"]


def test_status_preserves_stopped_and_unconfirmed_order_states(monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("MT5_COMMON_FILES_DIR", str(tmp_path))
    _write_ea_snapshot(tmp_path, running=False, status="STOPPED - EXISTING STOPS ACTIVE")
    stopped = client.get("/api/status").json()
    assert stopped["bot_status"] == "STOPPED"

    _write_ea_snapshot(tmp_path, status="BOT RUNNING")
    running = client.get("/api/status").json()
    assert running["bot_status"] == "BOT RUNNING"

    _write_ea_snapshot(tmp_path, status="CONNECTION ERROR - TRADING DISABLED")
    error = client.get("/api/status").json()
    assert error["bot_status"] == "CONNECTION ERROR - TRADING DISABLED"

    _write_ea_snapshot(tmp_path, status="TRADE REQUEST SUBMITTED")
    submitted = client.get("/api/status").json()
    assert submitted["bot_status"] == "TRADE REQUEST SUBMITTED"
    assert submitted["bot_status"] != "TRADE EXECUTED"


def test_status_reports_daily_limit_reached(monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("MT5_COMMON_FILES_DIR", str(tmp_path))
    _write_ea_snapshot(
        tmp_path,
        status="DAILY TRADE LIMIT REACHED",
        daily_trades=20,
        daily_limit=20,
        safety_block="Daily trade limit reached",
    )

    status = client.get("/api/status").json()

    assert status["bot_status"] == "DAILY TRADE LIMIT REACHED"
    assert status["trades_remaining"] == 0


def test_live_status_uses_current_quote_spread_when_ea_value_is_empty(monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("MT5_COMMON_FILES_DIR", str(tmp_path))
    _write_ea_snapshot(tmp_path, symbol="USDJPY", spread=0.0, symbols=[{"symbol": "USDJPY", "spread": 0.02}])
    monkeypatch.setattr(
        app_module,
        "_read_market_tags",
        lambda: {
            "connected": True,
            "tags": [{"symbol": "USDJPY", "bid": 157.9, "ask": 157.92, "spread": 0.02}],
            "error": "",
        },
    )

    status = client.get("/api/status").json()

    assert status["spread"] == 0.02


def test_manual_controls_require_mt5_connection_and_queue_commands(monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("MT5_COMMON_FILES_DIR", str(tmp_path))
    monkeypatch.setattr(
        app_module,
        "_read_market_tags",
        lambda: {"connected": False, "tags": [], "error": "MT5 terminal is not connected"},
    )
    disconnected = client.post("/api/control", json={"action": "start"})
    assert disconnected.status_code == 409

    monkeypatch.setattr(
        app_module,
        "_read_market_tags",
        lambda: {"connected": True, "tags": [], "error": ""},
    )
    queued_start = client.post("/api/control", json={"action": "START"})
    assert queued_start.status_code == 200
    assert queued_start.json()["queued"] is True
    assert "attach GoldFirstBot" in queued_start.json()["message"]
    assert client.get("/api/status").json()["pending_command"] == "START"

    _write_ea_snapshot(tmp_path)
    started = client.post("/api/control", json={"action": "START"})
    assert started.status_code == 200
    assert started.json()["queued"] is True
    assert started.json()["requested_action"] == "START"
    assert (tmp_path / "GoldFirstBot.command").read_text(encoding="ascii").strip() == "START"

    stopped = client.post("/api/control", json={"action": "stop"})
    assert stopped.status_code == 200
    assert (tmp_path / "GoldFirstBot.command").read_text(encoding="ascii").strip() == "STOP"


def test_stop_can_queue_when_mt5_is_connected_but_ea_is_not_attached(monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("MT5_COMMON_FILES_DIR", str(tmp_path))
    monkeypatch.setattr(
        app_module,
        "_read_market_tags",
        lambda: {"connected": True, "tags": [], "error": ""},
    )

    response = client.post("/api/control", json={"action": "STOP"})

    assert response.status_code == 200
    assert response.json()["queued"] is True
    assert (tmp_path / "GoldFirstBot.command").read_text(encoding="ascii").strip() == "STOP"
    assert client.get("/api/status").json()["pending_command"] == "STOP"


def test_remote_bridge_authenticates_heartbeat_and_dashboard_commands(monkeypatch) -> None:
    monkeypatch.setenv("MT5_BRIDGE_TOKEN", "bridge-secret")
    monkeypatch.setenv("DASHBOARD_ACCESS_TOKEN", "dashboard-secret")
    monkeypatch.setattr(app_module, "_remote_snapshot", None)
    monkeypatch.setattr(app_module, "_remote_received_at", 0.0)
    monkeypatch.setattr(app_module, "_remote_pending_command", "")
    monkeypatch.setattr(app_module, "_remote_command_delivered_at", 0.0)
    snapshot = {
        "connected": True,
        "running": False,
        "status": "STOPPED - PRESS START",
        "symbols": [],
        "daily_trades": 0,
        "daily_limit": 20,
        "positions": 0,
        "max_positions": 5,
    }

    assert client.post("/api/bridge/heartbeat", json=snapshot).status_code == 401
    assert client.get("/api/status").status_code == 401
    heartbeat = client.post(
        "/api/bridge/heartbeat",
        json=snapshot,
        headers={"X-MT5-Bridge-Token": "bridge-secret"},
    )
    assert heartbeat.status_code == 200
    assert client.get("/api/status", headers={"Authorization": "Bearer dashboard-secret"}).json()["data_state"] == "LIVE"

    queued = client.post(
        "/api/control",
        json={"action": "START"},
        headers={"Authorization": "Bearer dashboard-secret"},
    )
    assert queued.status_code == 200
    command_headers = {"X-MT5-Bridge-Token": "bridge-secret"}
    command = client.get("/api/bridge/command", headers=command_headers)
    assert command.text == "START"

    snapshot.update(running=True, status="RUNNING - WAITING FOR ENTRY")
    acknowledged = client.post("/api/bridge/heartbeat", json=snapshot, headers=command_headers)
    assert acknowledged.status_code == 200
    assert client.get("/api/bridge/command", headers=command_headers).text == "NONE"

    client.post("/api/control", json={"action": "START"}, headers={"Authorization": "Bearer dashboard-secret"})
    client.get("/api/bridge/command", headers=command_headers)
    snapshot.update(running=False, status="RISK PROTECTION ACTIVE - START REFUSED")
    client.post("/api/bridge/heartbeat", json=snapshot, headers=command_headers)
    assert client.get("/api/bridge/command", headers=command_headers).text == "NONE"


def test_openai_news_analysis_requires_dashboard_token(monkeypatch) -> None:
    monkeypatch.setenv("DASHBOARD_ACCESS_TOKEN", "dashboard-secret")
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)

    response = client.post("/api/news/analyze", json={"question": "Analyze gold"})

    assert response.status_code == 401


def test_dashboard_is_served_from_index_html() -> None:
    response = client.get("/")

    assert response.status_code == 200
    assert "JayTrade" in response.text


def test_python_order_route_is_disabled() -> None:
    response = client.post("/trade/multi", json={"symbols": ["XAUUSD"], "directions": ["BUY"]})

    assert response.status_code == 410


def test_tradingview_webhook_rejects_wrong_token(monkeypatch) -> None:
    monkeypatch.setenv("TRADINGVIEW_WEBHOOK_SECRET", "test-secret")

    response = client.post(
        "/webhook/tradingview",
        json={"token": "wrong", "symbol": "EURUSD", "message": "test"},
    )

    assert response.status_code == 401


def test_tradingview_webhook_stores_alert_without_token(monkeypatch) -> None:
    monkeypatch.setenv("TRADINGVIEW_WEBHOOK_SECRET", "test-secret")
    recent_alerts.clear()
    app_module.latest_trade_signal = None
    app_module.latest_signal_sequence = 0

    response = client.post(
        "/webhook/tradingview",
        json={
            "token": "test-secret",
            "symbol": "EURUSD",
            "action": "cross_up",
            "message": "fast EMA crossed above slow EMA",
        },
    )

    assert response.status_code == 200
    assert response.json()["available_for_mt5"] is False
    assert response.json()["signal_sequence"] == 0
    assert recent_alerts[0]["symbol"] == "EURUSD"
    assert "token" not in recent_alerts[0]


def test_tradingview_signal_feed_requires_secret_and_returns_latest_action(monkeypatch) -> None:
    monkeypatch.setenv("TRADINGVIEW_WEBHOOK_SECRET", "test-secret")
    recent_alerts.clear()
    app_module.latest_trade_signal = None
    app_module.latest_signal_sequence = 0

    response = client.post(
        "/webhook/tradingview",
        json={
            "token": "test-secret",
            "symbol": "OANDA:XAUUSD",
            "action": "BUY",
            "timeframe": "5",
            "message": "manual analysis alert",
        },
    )
    assert response.status_code == 200

    unauthorized = client.get("/signals/latest")
    assert unauthorized.status_code == 401

    signal = client.get("/signals/latest", headers={"X-Signal-Token": "test-secret"})
    assert signal.status_code == 200
    assert signal.json()["sequence"] == 1
    assert signal.json()["signal"]["symbol"] == "OANDA:XAUUSD"
    assert signal.json()["signal"]["action"] == "BUY"


def test_news_endpoint_returns_feed_freshness_and_articles(monkeypatch) -> None:
    news = {
        "fetched_at": "2026-10-16T11:06:51+00:00",
        "age_seconds": 12,
        "stale": False,
        "feeds_available": 2,
        "error": "",
        "articles": [{"title": "Gold and Treasury yields", "topics": ["Gold", "Yields"]}],
        "automated_trade_impact": False,
    }
    monkeypatch.setattr(app_module, "read_market_news", lambda force_refresh=False: news)

    response = client.get("/api/news?refresh=true")

    assert response.status_code == 200
    assert response.json() == news


def test_news_analysis_uses_headlines_without_enabling_trading(monkeypatch) -> None:
    class FakeResponses:
        def create(self, **kwargs):
            assert "Gold and Treasury yields" in kwargs["input"]
            assert "does not execute" in kwargs["instructions"]
            return SimpleNamespace(output_text="Yields and USD are possible gold drivers; uncertainty remains.")

    class FakeOpenAI:
        def __init__(self, api_key):
            self.responses = FakeResponses()

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(app_module, "OpenAI", FakeOpenAI)
    monkeypatch.setattr(
        app_module,
        "read_market_news",
        lambda: {
            "fetched_at": "2026-10-16T11:06:51+00:00",
            "articles": [{"title": "Gold and Treasury yields"}],
        },
    )

    response = client.post("/api/news/analyze", json={"question": "What is affecting gold?"})

    assert response.status_code == 200
    assert response.json()["automated_trade_impact"] is False
    assert response.json()["execution_enabled"] is False


def test_news_analysis_explains_openai_quota_errors(monkeypatch) -> None:
    class FakeResponses:
        def create(self, **kwargs):
            raise app_module.APIError(
                message="Quota exceeded",
                request=None,
                body={"error": {"code": "insufficient_quota"}},
            )

    class FakeOpenAI:
        def __init__(self, api_key):
            self.responses = FakeResponses()

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(app_module, "OpenAI", FakeOpenAI)
    monkeypatch.setattr(
        app_module,
        "read_market_news",
        lambda: {"fetched_at": "now", "articles": [{"title": "Gold and yields"}]},
    )

    response = client.post("/api/news/analyze", json={"question": "Analyze gold"})

    assert response.status_code == 502
    assert "API quota or billing is unavailable" in response.json()["detail"]