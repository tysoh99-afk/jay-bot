"""Read-only RSS news context for gold and major FX market drivers."""

from __future__ import annotations

from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from html.parser import HTMLParser
import re
import threading
import time
from typing import Any
from urllib.error import URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ElementTree


NEWS_FEEDS = (
    (
        "FXStreet",
        "https://www.fxstreet.com/rss/news",
    ),
    (
        "CNBC",
        "https://www.cnbc.com/id/100003114/device/rss/rss.html",
    ),
)
NEWS_CACHE_SECONDS = 120
NEWS_MAX_ITEMS = 30
NEWS_MAX_FEED_BYTES = 1_000_000
NEWS_TIMEOUT_SECONDS = 5

_TOPIC_TERMS = {
    "Gold": ("gold", "xau", "bullion", "precious metal"),
    "USD / Fed": ("usd", "u.s. dollar", "us dollar", "greenback", "federal reserve", "fed ", "fed's", "interest rate", "rate cut", "rate hike"),
    "Yields": ("yield", "treasury", "real rates", "bond market"),
    "Inflation / data": ("inflation", "cpi", "ppi", "payroll", "jobs report", "economic data"),
    "Risk / geopolitics": ("risk-off", "safe haven", "safe-haven", "geopolitical", "sanction", "conflict", "armed conflict", "military strike", "war in", "war with", "war between"),
    "Energy": ("oil", "crude", "energy prices"),
}
_GOLD_TERMS = ("gold", "xau", "xauusd", "bullion", "precious metal")
_MARKET_TERMS = tuple(term for terms in _TOPIC_TERMS.values() for term in terms)


def _contains_term(text: str, term: str) -> bool:
    phrase = r"\s+".join(re.escape(part) for part in term.strip().split())
    return bool(re.search(rf"(?<![a-z0-9]){phrase}(?![a-z0-9])", text))


class _TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []

    def handle_data(self, data: str) -> None:
        self.parts.append(data)


def _plain_text(value: str | None) -> str:
    parser = _TextExtractor()
    parser.feed(value or "")
    return re.sub(r"\s+", " ", " ".join(parser.parts)).strip()


def _published_at(value: str | None) -> str | None:
    if not value:
        return None
    try:
        parsed = parsedate_to_datetime(value)
    except (TypeError, ValueError, OverflowError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat()


def _safe_article_url(value: str | None) -> str:
    candidate = (value or "").strip()
    parsed = urlsplit(candidate)
    if parsed.scheme != "https" or not parsed.netloc:
        return ""
    return candidate


def _article_topics(title: str, summary: str) -> tuple[list[str], str]:
    text = f"{title} {summary}".casefold()
    topics = [
        topic
        for topic, terms in _TOPIC_TERMS.items()
        if any(_contains_term(text, term) for term in terms)
    ]
    direct_gold = any(_contains_term(text, term) for term in _GOLD_TERMS)
    return topics, "DIRECT GOLD" if direct_gold else "GOLD DRIVER"


def _parse_feed(content: bytes, feed_name: str) -> list[dict[str, Any]]:
    root = ElementTree.fromstring(content)
    articles: list[dict[str, Any]] = []
    for item in root.findall(".//item"):
        title = _plain_text(item.findtext("title"))
        summary = _plain_text(item.findtext("description"))
        link = _safe_article_url(item.findtext("link"))
        if not title or not link:
            continue
        text = f"{title} {summary}".casefold()
        if not any(_contains_term(text, term) for term in _MARKET_TERMS):
            continue
        topics, relevance = _article_topics(title, summary)
        source = _plain_text(item.findtext("source")) or feed_name
        articles.append({
            "title": title[:300],
            "summary": summary[:700],
            "url": link,
            "source": source[:100],
            "published_at": _published_at(item.findtext("pubDate")),
            "topics": topics,
            "gold_relevance": relevance,
        })
    return articles


_news_lock = threading.Lock()
_news_cache: dict[str, Any] = {
    "checked_epoch": 0.0,
    "success_epoch": 0.0,
    "articles": [],
    "successful_feeds": 0,
    "error": "",
}


def _fetch_feed(feed_name: str, url: str) -> list[dict[str, Any]]:
    request = Request(url, headers={"User-Agent": "JayTradeMonitor/1.0 (RSS reader)"})
    with urlopen(request, timeout=NEWS_TIMEOUT_SECONDS) as response:
        content = response.read(NEWS_MAX_FEED_BYTES + 1)
    if len(content) > NEWS_MAX_FEED_BYTES:
        raise ValueError(f"{feed_name} feed exceeded the size limit")
    return _parse_feed(content, feed_name)


def _cache_response(now: float) -> dict[str, Any]:
    success_epoch = float(_news_cache["success_epoch"])
    return {
        "fetched_at": datetime.fromtimestamp(success_epoch, timezone.utc).isoformat() if success_epoch else None,
        "age_seconds": max(0, int(now - success_epoch)) if success_epoch else None,
        "stale": not success_epoch or now - success_epoch > NEWS_CACHE_SECONDS,
        "feeds_available": _news_cache["successful_feeds"],
        "error": _news_cache["error"],
        "articles": [dict(article) for article in _news_cache["articles"]],
        "automated_trade_impact": False,
    }


def read_market_news(force_refresh: bool = False) -> dict[str, Any]:
    now = time.time()
    with _news_lock:
        if not force_refresh and now - float(_news_cache["checked_epoch"]) < NEWS_CACHE_SECONDS:
            return _cache_response(now)

        articles: list[dict[str, Any]] = []
        errors: list[str] = []
        successful_feeds = 0
        for feed_name, url in NEWS_FEEDS:
            try:
                articles.extend(_fetch_feed(feed_name, url))
                successful_feeds += 1
            except (OSError, URLError, TimeoutError, ValueError, ElementTree.ParseError) as error:
                errors.append(f"{feed_name}: {error}")

        deduplicated: dict[str, dict[str, Any]] = {}
        for article in articles:
            dedupe_key = article["url"] or article["title"].casefold()
            deduplicated.setdefault(dedupe_key, article)
        fresh_articles = list(deduplicated.values())
        fresh_articles.sort(
            key=lambda article: (
                article["published_at"] is not None,
                article["published_at"] or "",
                article["gold_relevance"] == "DIRECT GOLD",
            ),
            reverse=True,
        )

        _news_cache["checked_epoch"] = now
        _news_cache["error"] = "; ".join(errors)
        _news_cache["successful_feeds"] = successful_feeds
        if successful_feeds:
            _news_cache["success_epoch"] = now
            _news_cache["articles"] = fresh_articles[:NEWS_MAX_ITEMS]
        return _cache_response(now)