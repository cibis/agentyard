---
name: yahoo-finance
description: Get real-time stock quotes, historical OHLCV data, financial statements, analyst ratings, and market summaries from Yahoo Finance.
---

# Yahoo Finance Skill

Retrieve live and historical financial data from Yahoo Finance. No API key required.

## When to Use

- Stock price, market cap, P/E ratio, dividend yield
- Historical OHLCV price data for charting or analysis
- Income statement, balance sheet, cash flow data
- Analyst price targets and buy/sell/hold ratings
- Major index snapshot (S&P 500, NASDAQ, DOW, VIX, gold, oil, BTC)

## When NOT to Use

- Real-time options chains → use a dedicated options data source
- Insider filing data → use SEC EDGAR directly
- Crypto depth-of-book → use exchange APIs

---

## Commands

### Real-time Quote

```bash
curl -s "https://query1.finance.yahoo.com/v8/finance/chart/AAPL?interval=1d&range=1d" \
  -H "User-Agent: Mozilla/5.0" | \
  node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); \
    const r=d.chart.result[0]; \
    const m=r.meta; \
    console.log(JSON.stringify({symbol:m.symbol,price:m.regularMarketPrice,currency:m.currency,exchange:m.exchangeName},null,2))"
```

### Quote Summary (price + key stats)

```bash
curl -s "https://query1.finance.yahoo.com/v10/finance/quoteSummary/AAPL?modules=price,summaryDetail,financialData" \
  -H "User-Agent: Mozilla/5.0" | \
  node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); \
    const r=d.quoteSummary.result[0]; \
    console.log(JSON.stringify({price:r.price?.regularMarketPrice?.raw, \
      marketCap:r.price?.marketCap?.raw, \
      pe:r.summaryDetail?.trailingPE?.raw, \
      eps:r.summaryDetail?.trailingEps?.raw, \
      dividend:r.summaryDetail?.dividendYield?.raw, \
      targetPrice:r.financialData?.targetMeanPrice?.raw, \
      recommendation:r.financialData?.recommendationKey},null,2))"
```

### Historical OHLCV (last 30 days, daily)

```bash
curl -s "https://query1.finance.yahoo.com/v8/finance/chart/AAPL?interval=1d&range=1mo" \
  -H "User-Agent: Mozilla/5.0" | \
  node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); \
    const r=d.chart.result[0]; \
    const ts=r.timestamp; \
    const q=r.indicators.quote[0]; \
    const rows=ts.map((t,i)=>({date:new Date(t*1000).toISOString().slice(0,10), \
      open:q.open[i]?.toFixed(2),high:q.high[i]?.toFixed(2), \
      low:q.low[i]?.toFixed(2),close:q.close[i]?.toFixed(2),volume:q.volume[i]})); \
    console.log(JSON.stringify(rows,null,2))"
```

### Financial Statements

```bash
# Income statement (annual)
curl -s "https://query1.finance.yahoo.com/v10/finance/quoteSummary/AAPL?modules=incomeStatementHistory" \
  -H "User-Agent: Mozilla/5.0" | \
  node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); \
    console.log(JSON.stringify(d.quoteSummary.result[0].incomeStatementHistory,null,2))"
```

### Analyst Recommendations

```bash
curl -s "https://query1.finance.yahoo.com/v10/finance/quoteSummary/AAPL?modules=recommendationTrend,upgradeDowngradeHistory" \
  -H "User-Agent: Mozilla/5.0" | \
  node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); \
    console.log(JSON.stringify(d.quoteSummary.result[0],null,2))"
```

### Market Summary (indices snapshot)

```bash
curl -s "https://query1.finance.yahoo.com/v6/finance/quote/marketSummary" \
  -H "User-Agent: Mozilla/5.0" | \
  node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); \
    const items=d.marketSummaryResponse.result.map(r=>({symbol:r.symbol,price:r.regularMarketPrice?.raw,change:r.regularMarketChangePercent?.raw?.toFixed(2)+'%'})); \
    console.log(JSON.stringify(items,null,2))"
```

---

## Parameters

| Parameter | Values | Description |
|---|---|---|
| `interval` | `1m 5m 15m 1h 1d 1wk 1mo` | Bar period |
| `range` | `1d 5d 1mo 3mo 6mo 1y 2y 5y 10y ytd max` | Lookback window |
| `modules` | `price summaryDetail financialData incomeStatementHistory balanceSheetHistory cashflowStatementHistory recommendationTrend upgradeDowngradeHistory` | Quote summary modules |

## Notes

- Replace `AAPL` with any valid ticker (e.g. `MSFT`, `BTC-USD`, `GC=F` for gold futures, `^GSPC` for S&P 500)
- `node` is available in the container; no extra install needed
- Yahoo Finance may throttle rapid repeated requests — add `sleep 1` between bulk calls
- Data is delayed ~15 minutes for most exchanges
