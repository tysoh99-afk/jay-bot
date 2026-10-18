from datetime import datetime

from Python.analyze_backtest import load_results, summarize


def test_summarize_reports_risk_and_performance_metrics() -> None:
    rows = [
        {"position_id": str(index), "time": datetime(2026, 1, index + 1, 10), "symbol": "XAUUSD", "net_profit": profit}
        for index, profit in enumerate([10.0, -3.0, -2.0, 5.0])
    ]

    report = summarize(rows)

    assert report["trades"] == 4
    assert report["win_rate_percent"] == 50.0
    assert report["net_profit"] == 10.0
    assert report["profit_factor"] == 3.0
    assert report["expected_value_per_trade"] == 2.5
    assert report["maximum_drawdown"] == 5.0
    assert report["longest_losing_streak"] == 2
    assert report["by_symbol"]["XAUUSD"]["trades"] == 4
    assert report["sample_warning"] is not None


def test_load_results_deduplicates_position_ids(tmp_path) -> None:
    report_file = tmp_path / "GoldFirstBotResults.csv"
    report_file.write_text(
        "time,position_id,symbol,direction,volume,net_profit,currency\n"
        "2026.01.02 10:00:00,123,XAUUSD,BUY,0.02,8.5,USD\n"
        "2026.01.02 10:00:01,123,XAUUSD,BUY,0.02,8.5,USD\n",
        encoding="utf-8",
    )

    rows = load_results(report_file)

    assert len(rows) == 1
    assert rows[0]["net_profit"] == 8.5
    assert rows[0]["time"] == datetime(2026, 1, 2, 10)