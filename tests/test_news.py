from jaytrade.news import _article_topics, _parse_feed


def test_parse_feed_returns_gold_context_and_ignores_unsafe_links() -> None:
    feed = b"""<?xml version="1.0"?>
    <rss version="2.0"><channel>
      <item>
        <title><![CDATA[Gold steadies as US yields ease]]></title>
        <link>https://www.fxstreet.com/news/gold-yields</link>
        <pubDate>Fri, 16 Oct 2026 11:06:51 GMT</pubDate>
        <description><![CDATA[Gold holds gains as Treasury yields and the US Dollar soften.]]></description>
        <source>FXStreet</source>
      </item>
      <item>
        <title>Gold headline with unsafe URL</title>
        <link>javascript:alert(1)</link>
      </item>
      <item>
        <title>Unrelated headline</title>
        <link>https://example.com/unrelated</link>
      </item>
    </channel></rss>"""

    articles = _parse_feed(feed, "Test Feed")

    assert len(articles) == 1
    assert articles[0]["source"] == "FXStreet"
    assert articles[0]["gold_relevance"] == "DIRECT GOLD"
    assert articles[0]["topics"] == ["Gold", "USD / Fed", "Yields"]
    assert articles[0]["published_at"] == "2026-10-16T11:06:51+00:00"


def test_parse_feed_marks_macro_context_as_gold_driver() -> None:
    feed = b"""<rss><channel><item>
      <title>Federal Reserve comments move Treasury yields</title>
      <link>https://example.com/fed</link>
      <description>Markets assess the US Dollar and interest rates.</description>
    </item></channel></rss>"""

    article = _parse_feed(feed, "Test Feed")[0]

    assert article["gold_relevance"] == "GOLD DRIVER"
    assert article["topics"] == ["USD / Fed", "Yields"]


def test_topic_matching_does_not_treat_war_chest_as_geopolitics() -> None:
    topics, relevance = _article_topics(
        "Political action committee celebrates record war chest",
        "A fundraising report contains no comments on economic conditions.",
    )

    assert topics == []
    assert relevance == "GOLD DRIVER"