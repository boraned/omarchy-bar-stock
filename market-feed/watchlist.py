#!/usr/bin/env python3
"""Watchlist editor for the bar ticker (used by its right-click popup).

    watchlist.py list                 JSON {display_currency, currencies, assets}
    watchlist.py search <query>       JSON [{symbol, name, exchange, type, added}]
    watchlist.py add <symbol> [name]  add a symbol (checked against Yahoo first)
    watchlist.py remove <symbol>
    watchlist.py currency <code>      save the display currency (USD, CAD, TRY)
"""
import json
import re
import sys

sys.dont_write_bytecode = True
import fetch_markets as feed  # noqa: E402

# Yahoo quote types offered in search, most useful first.
SEARCH_TYPES = {
    "EQUITY": "Stock", "ETF": "ETF", "INDEX": "Index", "CRYPTOCURRENCY": "Crypto",
    "CURRENCY": "FX", "FUTURE": "Futures", "MUTUALFUND": "Fund",
}
TYPE_RANK = {kind: rank for rank, kind in enumerate(SEARCH_TYPES.values())}
NAME_SUFFIXES = re.compile(
    r"(,?\s+(inc\.?|incorporated|corp\.?|corporation|co\.?|company|ltd\.?|limited|plc|"
    r"n\.?v\.?|s\.?a\.?|a\.?g\.?|se|holdings?|group|class [a-z]|common stock|"
    r"\(the\)|usd|futures?,?.*))+\s*$", re.IGNORECASE)


def short_name(name, symbol):
    """'Apple Inc.' → 'Apple', 'Bitcoin USD' → 'Bitcoin'."""
    name = re.sub(r"\s+", " ", str(name or "")).strip()
    cleaned = NAME_SUFFIXES.sub("", name).strip(" ,.-")
    cleaned = cleaned or name or symbol
    return cleaned if len(cleaned) <= 22 else cleaned[:21].rstrip() + "…"


def symbols(config):
    return {str(asset.get("symbol", "")).upper() for asset in config["assets"] if isinstance(asset, dict)}


def cmd_list():
    config = feed.load_config()
    print(json.dumps({
        "display_currency": config.get("display_currency", "USD"),
        "currencies": [{"code": code, **info} for code, info in feed.CURRENCIES.items()],
        "assets": [{"symbol": a["symbol"], "label": a.get("label") or a["symbol"]}
                   for a in config["assets"] if isinstance(a, dict) and a.get("symbol")],
    }, ensure_ascii=False))


def cmd_search(query):
    query = query.strip()
    if not query:
        print("[]")
        return
    try:
        quotes = feed.get_json(feed.search_url(query, 16)).get("quotes", [])
    except Exception:
        print("null")
        return
    added = symbols(feed.load_config())
    results = []
    for item in quotes:
        kind = SEARCH_TYPES.get(str(item.get("quoteType", "")).upper())
        symbol = item.get("symbol")
        if not kind or not symbol:
            continue
        name = re.sub(r"\s+", " ", item.get("longname") or item.get("shortname") or symbol).strip()
        results.append({
            "symbol": symbol, "name": name, "label": short_name(name, symbol),
            "exchange": item.get("exchDisp") or item.get("exchange") or "",
            "type": kind, "added": symbol.upper() in added,
        })
    exact = query.upper()
    results.sort(key=lambda r: (r["symbol"].upper() != exact, TYPE_RANK[r["type"]]))
    print(json.dumps(results[:8], ensure_ascii=False))


def cmd_add(symbol, name=""):
    symbol = symbol.strip()
    config = feed.load_config()
    if symbol.upper() in symbols(config):
        return
    quoted = feed.fetch_quote(symbol)
    if not quoted or quoted[0] is None:
        sys.exit(f"watchlist: no quote for {symbol}")
    label = short_name(name or quoted[3], symbol)
    price_usd, _ = feed.to_usd(quoted[0], None, quoted[2], {})
    config["assets"].append({"symbol": symbol, "label": label,
                             "digits": feed.default_digits(price_usd if price_usd is not None else quoted[0])})
    feed.save_config(config)


def cmd_remove(symbol):
    config = feed.load_config()
    keep = [a for a in config["assets"]
            if not (isinstance(a, dict) and str(a.get("symbol", "")).upper() == symbol.strip().upper())]
    if len(keep) != len(config["assets"]):
        config["assets"] = keep
        feed.save_config(config)


def cmd_currency(code):
    code = code.strip().upper()
    if code not in feed.CURRENCIES:
        sys.exit(f"watchlist: unsupported currency {code}")
    config = feed.load_config()
    if config.get("display_currency") != code:
        config["display_currency"] = code
        feed.save_config(config)


def main(argv):
    command, args = (argv[1] if len(argv) > 1 else ""), argv[2:]
    if command == "list" and not args:
        cmd_list()
    elif command == "search" and len(args) == 1:
        cmd_search(args[0])
    elif command == "add" and 1 <= len(args) <= 2:
        cmd_add(*args)
    elif command == "remove" and len(args) == 1:
        cmd_remove(args[0])
    elif command == "currency" and len(args) == 1:
        cmd_currency(args[0])
    else:
        sys.exit(__doc__.strip())


if __name__ == "__main__":
    main(sys.argv)
