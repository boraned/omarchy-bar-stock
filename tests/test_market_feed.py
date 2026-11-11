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

    def test_add_and_remove_round_trip(self):
        quote = (250.0, 240.0, "USD", "Tesla, Inc.")
        with patch.object(feed, "fetch_quote", return_value=quote):
            watchlist.cmd_add("TSLA", "Tesla, Inc.")
            watchlist.cmd_add("tsla")  # duplicates are ignored
        self.assertEqual(self.assets(), ["AAPL", "TSLA"])
        self.assertEqual(feed.load_config()["assets"][1]["label"], "Tesla")
        watchlist.cmd_remove("aapl")
        self.assertEqual(self.assets(), ["TSLA"])

    def currencies(self):
        return feed.configured_currencies(feed.load_config())

    def test_a_watchlist_without_currencies_lists_usd_only(self):
        self.assertEqual(self.currencies(), ["USD"])
        self.assertEqual(feed.display_currency(feed.load_config()), "USD")
        with self.assertRaises(SystemExit):
            watchlist.cmd_currency("EUR")  # not listed yet

    def test_currencies_are_added_in_order_after_a_rate_check(self):
        with patch.object(feed, "fetch_quote", return_value=(0.9, 0.9, "EUR", "")):
            watchlist.cmd_currency_add("eur")
            watchlist.cmd_currency_add("TRY")
            watchlist.cmd_currency_add("EUR")  # already listed
        self.assertEqual(self.currencies(), ["USD", "EUR", "TRY"])
        watchlist.cmd_currency("try")
        self.assertEqual(feed.load_config()["display_currency"], "TRY")
        with patch.object(feed, "fetch_quote", return_value=None), self.assertRaises(SystemExit):
            watchlist.cmd_currency_add("XYZ")  # Yahoo has no rate for it
        with self.assertRaises(SystemExit):
            watchlist.cmd_currency_add("EURO")
        self.assertEqual(self.currencies(), ["USD", "EUR", "TRY"])

    def test_removing_currencies_keeps_one_and_moves_the_display(self):
        with patch.object(feed, "fetch_quote", return_value=(0.9, 0.9, "EUR", "")):
            watchlist.cmd_currency_add("EUR")
        watchlist.cmd_currency("EUR")
        watchlist.cmd_currency_remove("eur")
        self.assertEqual(self.currencies(), ["USD"])
        self.assertEqual(feed.load_config()["display_currency"], "USD")
        with self.assertRaises(SystemExit):
            watchlist.cmd_currency_remove("USD")  # the last one stays
        watchlist.cmd_currency_remove("JPY")  # not listed: nothing to do
        self.assertEqual(self.currencies(), ["USD"])

    def test_list_reports_the_listed_currencies(self):
        path = feed.user_config_path()
        config = json.loads(path.read_text(encoding="utf-8"))
        config.update(currencies=["usd", "TRY", "TRY", "nope"], display_currency="JPY")
        path.write_text(json.dumps(config), encoding="utf-8")
        with patch("sys.stdout.write") as write:
            watchlist.cmd_list()
        data = json.loads("".join(call.args[0] for call in write.call_args_list))
        self.assertEqual(data["currencies"], [{"code": "USD", "symbol": "$", "name": "US Dollar"},
                                              {"code": "TRY", "symbol": "₺", "name": "Turkish Lira"}])
        self.assertEqual(data["display_currency"], "USD")  # JPY isn't listed
        self.assertEqual(data["assets"], [{"symbol": "AAPL", "label": "Apple"}])

    def test_the_menu_can_add_many_currencies(self):
        with patch("sys.stdout.write") as write:
            watchlist.cmd_currencies()
        known = json.loads("".join(call.args[0] for call in write.call_args_list))
        codes = [entry["code"] for entry in known]
        self.assertEqual(len(codes), len(set(codes)))
        self.assertTrue({"USD", "EUR", "GBP", "JPY", "CAD", "TRY"} <= set(codes))
        self.assertTrue(all(entry["symbol"] and entry["name"] for entry in known))

    def test_unknown_symbol_is_not_added(self):
        with patch.object(feed, "fetch_quote", return_value=None), self.assertRaises(SystemExit):
            watchlist.cmd_add("NOPE123")
        self.assertEqual(self.assets(), ["AAPL"])

    def test_short_names(self):
        self.assertEqual(watchlist.short_name("Apple Inc.", "AAPL"), "Apple")
        self.assertEqual(watchlist.short_name("Bitcoin USD", "BTC-USD"), "Bitcoin")
        self.assertEqual(watchlist.short_name("NVIDIA Corporation", "NVDA"), "NVIDIA")
        self.assertEqual(watchlist.short_name("", "XYZ"), "XYZ")


class FeedOutputTests(unittest.TestCase):
    """main() end to end with Yahoo stubbed out."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {"XDG_CONFIG_HOME": self.tmp.name + "/config",
                                           "XDG_STATE_HOME": self.tmp.name + "/state"})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def run_main(self, quotes):
        def fake_get_json(url):
            symbol = url.split("/chart/")[1].split("?")[0].replace("%5E", "^")
            if symbol not in quotes:
                raise OSError("offline")
            price, previous, currency = quotes[symbol]
            return {"chart": {"result": [{"meta": {"regularMarketPrice": price,
                                                   "chartPreviousClose": previous,
                                                   "currency": currency}}]}}
        with patch.object(feed, "get_json", side_effect=fake_get_json), patch("sys.stdout.write") as write:
            feed.main(["fetch_markets.py"])
        return json.loads("".join(call.args[0] for call in write.call_args_list))

    def test_a_new_user_sees_dollars_and_no_pairs(self):
        bundled = json.loads(feed.CONFIG.read_text(encoding="utf-8"))
        self.assertEqual(bundled["currencies"], ["USD"])
        out = self.run_main({a["symbol"]: (100.0, 99.0, "USD") for a in bundled["assets"]})
        self.assertTrue(feed.user_config_path().is_file())
        self.assertEqual(out["status"], "LIVE")
        self.assertEqual(out["currency"]["target"], "USD")
        self.assertEqual(out["display_currencies"], [{"code": "USD", "symbol": "$"}])
        self.assertEqual(out["currencies"], [])

    def test_listed_currencies_drive_the_rate_and_pairs(self):
        path = feed.user_config_path()
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"display_currency": "TRY", "currencies": ["USD", "CAD", "TRY"],
                                    "assets": [{"symbol": "THYAO.IS", "label": "THY", "digits": 2}]}),
                        encoding="utf-8")
        out = self.run_main({"CAD=X": (1.4, 1.4, "CAD"), "TRY=X": (50.0, 50.0, "TRY"),
                             "THYAO.IS": (300.0, 290.0, "TRY")})
        self.assertEqual(out["currency"], {"source": "USD", "target": "TRY", "symbol": "₺", "rate": 50.0})
        self.assertEqual({p["symbol"] for p in out["currencies"]}, {"USD/TRY", "CAD/TRY"})
        self.assertEqual([c["code"] for c in out["display_currencies"]], ["USD", "CAD", "TRY"])
        self.assertAlmostEqual(out["assets"][0]["price"], 6.0)  # lira listing, normalized to USD


class SearchUrlTests(unittest.TestCase):
    def test_search_and_chart_urls_pass_the_host_allowlist(self):
        feed.validate_market_url(feed.search_url("apple"))
        feed.validate_market_url(feed.chart_url("^GSPC"))
        self.assertIn("%5EGSPC", feed.chart_url("^GSPC"))


if __name__ == "__main__":
    unittest.main()
