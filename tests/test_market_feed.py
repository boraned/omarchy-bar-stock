"""Market feed and watchlist editor behaviour (no network)."""
import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

PLUGIN = Path(__file__).resolve().parents[1]
FEED_DIR = PLUGIN / "market-feed"


def load(name, filename):
    sys.path.insert(0, str(FEED_DIR))
    try:
        spec = importlib.util.spec_from_file_location(name, FEED_DIR / filename)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        sys.path.remove(str(FEED_DIR))


feed = load("fetch_markets", "fetch_markets.py")
sys.modules["fetch_markets"] = feed
watchlist = load("watchlist", "watchlist.py")


class CurrencyPairTests(unittest.TestCase):
    QUOTES = {"USD": (1.0, 1.0), "CAD": (1.40, 1.40), "TRY": (50.0, 49.0)}

    def test_pairs_price_other_currencies_in_the_display_currency(self):
        pairs = feed.build_currency_pairs(self.QUOTES)
        for target, expected in (("USD", {"CAD/USD", "TRY/USD"}),
                                 ("CAD", {"USD/CAD", "TRY/CAD"}),
                                 ("TRY", {"USD/TRY", "CAD/TRY"})):
            with self.subTest(target=target):
                shown = feed.displayed_pairs(pairs, target)
                self.assertEqual({pair["symbol"] for pair in shown}, expected)

    def test_usd_mode_shows_dollars_per_lira(self):
        pairs = feed.displayed_pairs(feed.build_currency_pairs(self.QUOTES), "USD")
        lira = next(pair for pair in pairs if pair["symbol"] == "TRY/USD")
        self.assertAlmostEqual(lira["price"], 1 / 50.0)
        self.assertTrue(lira["is_currency_pair"] and lira["direct_target"])


class ConversionTests(unittest.TestCase):
    def test_foreign_and_minor_unit_quotes_are_normalized_to_usd(self):
        rates = {"TRY": (50.0, 50.0), "GBP": (0.8, 0.8)}
        self.assertEqual(feed.to_usd(500.0, 450.0, "TRY", rates), (10.0, 9.0))
        price, _ = feed.to_usd(800.0, None, "GBp", rates)
        self.assertAlmostEqual(price, 10.0)
        self.assertEqual(feed.to_usd(5.0, 4.0, "USD", rates), (5.0, 4.0))

    def test_unknown_currency_yields_no_price_instead_of_a_wrong_one(self):
        with patch.object(feed, "fetch_quote", return_value=None):
            self.assertEqual(feed.to_usd(10.0, 9.0, "XYZ", {}), (None, None))


class WatchlistTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {"XDG_CONFIG_HOME": self.tmp.name})
        self.env.start()
        target = feed.user_config_path()
        target.parent.mkdir(parents=True)
        target.write_text(json.dumps({"display_currency": "USD", "assets": [
            {"symbol": "AAPL", "label": "Apple", "digits": 2}]}), encoding="utf-8")

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def assets(self):
        return [a["symbol"] for a in feed.load_config()["assets"]]

    def test_add_remove_and_currency_round_trip(self):
        quote = (250.0, 240.0, "USD", "Tesla, Inc.")
        with patch.object(feed, "fetch_quote", return_value=quote):
            watchlist.cmd_add("TSLA", "Tesla, Inc.")
            watchlist.cmd_add("tsla")  # duplicates are ignored
        self.assertEqual(self.assets(), ["AAPL", "TSLA"])
        self.assertEqual(feed.load_config()["assets"][1]["label"], "Tesla")
        watchlist.cmd_remove("aapl")
        self.assertEqual(self.assets(), ["TSLA"])
        watchlist.cmd_currency("try")
        self.assertEqual(feed.load_config()["display_currency"], "TRY")
        with self.assertRaises(SystemExit):
            watchlist.cmd_currency("EUR")

    def test_unknown_symbol_is_not_added(self):
        with patch.object(feed, "fetch_quote", return_value=None), self.assertRaises(SystemExit):
            watchlist.cmd_add("NOPE123")
        self.assertEqual(self.assets(), ["AAPL"])

    def test_short_names(self):
        self.assertEqual(watchlist.short_name("Apple Inc.", "AAPL"), "Apple")
        self.assertEqual(watchlist.short_name("Bitcoin USD", "BTC-USD"), "Bitcoin")
        self.assertEqual(watchlist.short_name("NVIDIA Corporation", "NVDA"), "NVIDIA")
        self.assertEqual(watchlist.short_name("", "XYZ"), "XYZ")


class SearchUrlTests(unittest.TestCase):
    def test_search_and_chart_urls_pass_the_host_allowlist(self):
        feed.validate_market_url(feed.search_url("apple"))
        feed.validate_market_url(feed.chart_url("^GSPC"))
        self.assertIn("%5EGSPC", feed.chart_url("^GSPC"))


if __name__ == "__main__":
    unittest.main()
