#!/usr/bin/env python3
"""Market feed for the bar ticker.

    fetch_markets.py [USD|CAD|TRY]

Prints one JSON object: status, display currency + its USD rate, assets (USD
prices; the ticker converts them) and currency pairs (already final values).
Without an argument the display currency saved in the watchlist is used.
"""
import json
import os
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import quote, urlencode, urlsplit

PROJECT_DIR = Path(__file__).resolve().parent
CONFIG = PROJECT_DIR / "markets.json"
ALLOWED_MARKET_HOSTS = {"query1.finance.yahoo.com", "query2.finance.yahoo.com"}
USER_AGENT = "omarchy-bar-stock/1.0"

# Display currencies offered by the ticker popup. Yahoo's "<CODE>=X" chart is
# the USD→CODE rate.
CURRENCIES = {
    "USD": {"symbol": "$", "name": "US Dollar"},
    "CAD": {"symbol": "C$", "name": "Canadian Dollar"},
    "TRY": {"symbol": "₺", "name": "Turkish Lira"},
}
# Quotes in minor units (pence, agorot, cents) → (major currency, divisor).
MINOR_UNITS = {"GBp": ("GBP", 100), "GBX": ("GBP", 100), "ILA": ("ILS", 100), "ZAc": ("ZAR", 100)}


def absolute_xdg_home(variable, fallback):
    configured = os.environ.get(variable, "")
    candidate = Path(configured) if configured else fallback
    return candidate if candidate.is_absolute() else fallback


def user_config_path():
    config_home = absolute_xdg_home("XDG_CONFIG_HOME", Path.home() / ".config")
    return config_home / "omarchy" / "market-ticker" / "markets.json"


def state_path():
    state_home = absolute_xdg_home("XDG_STATE_HOME", Path.home() / ".local" / "state")
    return state_home / "omarchy" / "market-ticker" / "previous.json"


def ensure_user_config(target=None, default=CONFIG):
    """Create a private user watchlist once; never replace later edits."""
    target = Path(target or user_config_path())
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        with target.open("x", encoding="utf-8") as output:
            output.write(Path(default).read_text(encoding="utf-8"))
    except FileExistsError:
        pass
    return target


def load_config(path=None):
    path = ensure_user_config(path)
    with path.open(encoding="utf-8") as handle:
        config = json.load(handle)
    if not isinstance(config.get("assets"), list):
        config["assets"] = []
    return config


def save_config(config, path=None):
    """Atomically rewrite the user watchlist, one asset per line."""
    path = Path(path or user_config_path())
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["{"]
    for key, value in config.items():
        if key != "assets":
            lines.append(f"  {json.dumps(key)}: {json.dumps(value, ensure_ascii=False)},")
    assets = [json.dumps(asset, ensure_ascii=False, separators=(", ", ": "))
              for asset in config.get("assets", [])]
    lines.append('  "assets": [')
    if assets:
        lines.append(",\n".join("    " + asset for asset in assets))
    lines.append("  ]")
    lines.append("}")
    temporary = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    temporary.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def validate_market_url(url):
    """Reject non-HTTPS, local-file, credentialed, or non-Yahoo endpoints."""
    try:
        parsed = urlsplit(str(url))
        host = parsed.hostname or ""
        port = parsed.port
    except ValueError as error:
        raise ValueError("invalid market-data URL") from error
    if (parsed.scheme.lower() != "https" or host not in ALLOWED_MARKET_HOSTS
            or parsed.username is not None or parsed.password is not None
            or port not in (None, 443)):
        raise ValueError("market-data URLs must use HTTPS on an approved Yahoo Finance host")
    return str(url)


class YahooRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        validate_market_url(new_url)
        return super().redirect_request(request, response, code, message, headers, new_url)


def get_json(url, timeout=10):
    request = urllib.request.Request(validate_market_url(url), headers={"User-Agent": USER_AGENT})
    opener = urllib.request.build_opener(YahooRedirectHandler())
    with opener.open(request, timeout=timeout) as response:
        return json.load(response)


def chart_url(symbol):
    return ("https://query1.finance.yahoo.com/v8/finance/chart/"
            + quote(str(symbol), safe="=-.") + "?range=1d&interval=1m")


def search_url(query, count=10):
    return ("https://query2.finance.yahoo.com/v1/finance/search?"
            + urlencode({"q": query, "quotesCount": count, "newsCount": 0, "listsCount": 0}))


def chart_quote(payload):
    """(price, previous close, quote currency, name) from a chart response."""
    result = payload["chart"]["result"][0]
    meta = result["meta"]
    price = meta.get("regularMarketPrice")
    previous = meta.get("chartPreviousClose") or meta.get("previousClose")
    if price is None:
        closes = result.get("indicators", {}).get("quote", [{}])[0].get("close", [])
        price = next((x for x in reversed(closes) if x is not None), None)
    return (float(price) if price is not None else None,
            float(previous) if previous is not None else None,
            meta.get("currency") or "USD",
            meta.get("shortName") or meta.get("longName") or "")


def chart_price(payload):
    price, previous, _, _ = chart_quote(payload)
    return price, previous


def fetch_quote(symbol):
    try:
        return chart_quote(get_json(chart_url(symbol)))
    except Exception:
        return None


def positive(value):
    return value if value and value > 0 else None


def usd_rate(code, cache):
    """USD→code rate as (now, previous close); (1, 1) for USD."""
    if code == "USD":
        return (1.0, 1.0)
    if code not in cache:
        quoted = fetch_quote(f"{code}=X")
        cache[code] = (positive(quoted[0]), positive(quoted[1])) if quoted else (None, None)
    return cache[code]


def to_usd(price, previous, currency, rates):
    """Normalize a quote in any currency to USD; (None, None) when unknown."""
    code, divisor = MINOR_UNITS.get(currency, (str(currency).upper(), 1))
    price = price / divisor if price is not None else None
    previous = previous / divisor if previous is not None else None
    if code == "USD":
        return price, previous
    now, before = usd_rate(code, rates)
    if not now or price is None:
        return None, None
    return price / now, (previous / (before or now) if previous is not None else None)


def default_digits(price):
    return 4 if price is not None and abs(price) < 1 else 2


def build_currency_pairs(quotes):
    """Every cross among USD, CAD and TRY from USD-based Yahoo quotes."""
    pairs = []
    for base, targets in (("USD", ("CAD", "TRY")),
                          ("CAD", ("USD", "TRY")),
                          ("TRY", ("CAD", "USD"))):
        base_now, base_previous = quotes.get(base, (None, None))
        for target in targets:
            target_now, target_previous = quotes.get(target, (None, None))
            rate = (target_now / base_now if base_now and target_now else None)
            prior = (target_previous / base_previous
                     if base_previous and target_previous else None)
            change = (rate / prior - 1) * 100 if rate is not None and prior else None
            pairs.append({
                "symbol": f"{base}/{target}", "label": f"{base}/{target}",
                "group": "CURRENCIES", "is_currency_pair": True,
                "direct_target": True, "digits": 6 if base == "TRY" else 4,
                "price": rate, "change_pct": change,
            })
    return pairs


def displayed_pairs(pairs, target):
    """Each other currency priced in the display currency (USD mode: CAD/USD
    and TRY/USD, i.e. how many dollars one Canadian dollar and one lira buy)."""
    return [pair for pair in pairs if pair["symbol"].endswith("/" + target)]


def fetch_asset(asset, rates):
    """(price, previous close, already-in-target) for one watchlist entry."""
    url = asset.get("url") or chart_url(asset["symbol"])
    direct = bool(asset.get("direct_target", False))
    try:
        price, previous, currency, _ = chart_quote(get_json(url))
        if asset.get("invert_price") and price:
            price = 1.0 / price
            previous = 1.0 / previous if previous else None
        if asset.get("conversion_url") and price is not None:
            conversion, _ = chart_price(get_json(asset["conversion_url"]))
            if conversion is not None:
                price *= conversion
                previous = previous * conversion if previous is not None else None
            direct = True
        elif not direct:
            price, previous = to_usd(price, previous, currency, rates)
    except Exception:
        price, previous = None, None
    return price, previous, direct


def main(argv=None):
    argv = sys.argv if argv is None else argv
    config = load_config()
    requested = str(argv[1] if len(argv) > 1 else config.get("display_currency", "USD")).upper()
    if requested not in CURRENCIES:
        requested = "USD"
    try:
        with state_path().open(encoding="utf-8") as handle:
            old = json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError):
        old = {}

    assets = [asset for asset in config["assets"] if isinstance(asset, dict) and asset.get("symbol")]
    rates = {}
    with ThreadPoolExecutor(max_workers=8) as pool:
        # USD→CAD and USD→TRY drive the display rate, FX pairs and conversions.
        fx = {code: pool.submit(fetch_quote, f"{code}=X") for code in CURRENCIES if code != "USD"}
        for code, future in fx.items():
            quoted = future.result()
            rates[code] = (positive(quoted[0]), positive(quoted[1])) if quoted else (None, None)
        results = list(pool.map(lambda asset: fetch_asset(asset, rates), assets))

    usd_quotes = {code: usd_rate(code, rates) for code in CURRENCIES}
    currency = {"source": "USD", "target": requested,
                "symbol": CURRENCIES[requested]["symbol"],
                "rate": usd_quotes[requested][0]}
    output = {"profile": requested, "status": "LOADING", "currency": currency, "assets": [],
              "currencies": displayed_pairs(build_currency_pairs(usd_quotes), requested)}

    successful = 0
    for asset, (price, previous_close, direct) in zip(assets, results):
        prior = old.get(asset["symbol"])
        comparison = previous_close if previous_close is not None else prior
        change_pct = None if price is None or not comparison else (price - comparison) / comparison * 100
        output["assets"].append({
            "symbol": asset["symbol"], "label": asset.get("label") or asset["symbol"],
            "digits": asset.get("digits", default_digits(price)),
            "direct_target": direct, "price": price, "change_pct": change_pct,
        })
        if price is not None:
            successful += 1
            old[asset["symbol"]] = price

    fx_live = [usd_quotes[code][0] is not None for code in CURRENCIES]
    output["status"] = ("LIVE" if successful == len(assets) and all(fx_live)
                        else "PARTIAL" if successful or any(fx_live[1:])
                        else "OFFLINE")
    output["message"] = {"LIVE": "live", "PARTIAL": "some market or FX prices unavailable",
                         "OFFLINE": "connection unavailable; prices unavailable"}[output["status"]]

    state_file = state_path()
    state_file.parent.mkdir(parents=True, exist_ok=True)
    temporary_state = state_file.with_name(f"{state_file.name}.{os.getpid()}.tmp")
    with temporary_state.open("w", encoding="utf-8") as handle:
        json.dump(old, handle, separators=(",", ":"))
    os.replace(temporary_state, state_file)
    print(json.dumps(output, separators=(",", ":"), ensure_ascii=False))


if __name__ == "__main__":
    main()
