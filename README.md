# omarchy-bar-stock

Scrolling stock, crypto and currency quotes for the [Omarchy](https://omarchy.org) bar. Right-click the ticker to change the display currency or add and remove stocks. The menu opens where you clicked and uses your Omarchy theme.

- Quotes from Yahoo Finance, no API key. They refresh every 2 minutes and show green or red with the day's change.
- **Currency**: prices start in US dollars. Add the currencies you want to convert to, then click one to show prices in it. With two or more, the ticker also shows each one priced in the one you picked, e.g. `TRY/USD` (dollars per lira) in USD mode.
- **Watchlist**: search Yahoo Finance for stocks, ETFs, crypto, indices and futures, and add or remove them. Prices listed in other currencies are converted through USD.
- Prices are written as `1.234,56`.

## Requirements

- Omarchy 4.5 or newer (tested on 4.5.0), with the bar at the top or bottom.
- `python3` (standard library only).
- Internet access to `query1.finance.yahoo.com` and `query2.finance.yahoo.com`.

## Install

```sh
omarchy plugin add https://github.com/boraned/omarchy-bar-stock.git --enable
```

Pick a bar section when it asks. To move it later:

```sh
omarchy bar move omarchy-bar-stock --section right
```

The ticker is 480 px wide. To change that, add `width` to its entry in `~/.config/omarchy/shell.json`:

```json
{ "id": "omarchy-bar-stock", "width": 640 }
```

## Use

Right-click the ticker to open the menu.

| Key | Action |
|---|---|
| Type | Search |
| ↑ / ↓ | Move through the results or the watchlist |
| Enter | Add or remove the selected search result |
| Delete | Remove the selected watchlist entry |
| Esc | Clear the search, then close |

Clicking a result adds it (a check mark means it's already in your watchlist; click again to remove it). With the search empty, the list shows your watchlist with a × on each row.

To add a currency, click **+** next to CURRENCY, type a code or name (`eur`, `yen`), then press Enter or click the match. Hover a currency and click its **×** to remove it; one always stays. Three currencies fit across the menu; with more, the row scrolls sideways (mouse wheel or drag).

## Watchlist file

On first run the bundled watchlist (major indices, the largest US stocks, gold, oil, Bitcoin and Ethereum) is copied to `~/.config/omarchy/market-ticker/markets.json`, and the menu edits that copy. You can also edit it from a terminal:

```sh
cd ~/.config/omarchy/plugins/omarchy-bar-stock/market-feed
python3 watchlist.py search tesla
python3 watchlist.py add TSLA
python3 watchlist.py remove TSLA
python3 watchlist.py currency-add CAD
python3 watchlist.py currency CAD
python3 watchlist.py currency-remove CAD
```

The last prices, used for the up and down arrows, are kept in `~/.local/state/omarchy/market-ticker/previous.json`.

## Update and remove

```sh
omarchy plugin update omarchy-bar-stock
omarchy plugin remove omarchy-bar-stock
```

Removing the plugin leaves your watchlist and price files; delete the two paths above to remove those too.

## Tests

```sh
python3 -m unittest discover -s tests
```

## Notes

Yahoo Finance's endpoints are unofficial. Quotes can be delayed, rate-limited or briefly unavailable, in which case the ticker says so and retries. Not investment advice.

## License

MIT
