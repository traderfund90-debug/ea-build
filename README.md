# HighWinRate EA — MetaTrader 5 Expert Advisor

A multi-indicator confluence EA designed for high win-rate trading on forex and
gold markets.

## Strategy Overview

The EA combines four independent signals that must align before entering a trade.
This confluence approach filters out low-quality setups and keeps win rate high.

| Component | Role |
|---|---|
| **200 EMA** | Macro trend filter — only trade in trend direction |
| **21/50 EMA** | Momentum confirmation — fast above slow = bullish |
| **RSI (14)** | Entry timing — buy oversold, sell overbought |
| **Bollinger Bands** | Price extreme confirmation — near band = mean-revert |

### Entry Conditions

**BUY** (all must be true):
1. Close price above 200 EMA (uptrend)
2. Fast EMA (21) above Slow EMA (50)
3. RSI below 35 (oversold pullback in uptrend)
4. Price near or touching lower Bollinger Band

**SELL** (all must be true):
1. Close price below 200 EMA (downtrend)
2. Fast EMA (21) below Slow EMA (50)
3. RSI above 65 (overbought rally in downtrend)
4. Price near or touching upper Bollinger Band

Secondary trigger: EMA crossover in trend direction with neutral RSI.

### Exit Logic
- **Take Profit**: 1.0 × ATR (tight TP = higher win rate)
- **Stop Loss**: 1.5 × ATR (wider SL = avoid noise-triggered stops)
- **Trailing Stop**: 1.0 × ATR (locks in profits as trade moves)
- **Opposite signal**: Closes trade early if trend reverses

## Risk Management
- **Risk per trade**: 1% of account balance (adjustable)
- **Max open trades**: 2 simultaneous positions
- **Lot sizing**: Automatic, based on ATR stop distance
- **Session filter**: Only trades 07:00–20:00 server time (London + NY)

## Recommended Settings

| Parameter | Value | Notes |
|---|---|---|
| Pairs | EURUSD, GBPUSD, XAUUSD | High liquidity, tight spreads |
| Timeframe | H1 | Best signal quality |
| Risk % | 0.5–1.0 | Conservative, protects capital |
| ATR TP Multi | 1.0 | Tight TP keeps win rate high |
| ATR SL Multi | 1.5 | Absorbs normal price noise |

## Installation

1. Copy `HighWinRate_EA.mq5` to `MQL5/Experts/` in your MT5 data folder
2. Open MetaEditor and compile the file (F7)
3. Attach to an H1 chart of your chosen pair
4. Load `HighWinRate_EA.set` via the EA settings dialog
5. Enable `Allow Algo Trading` on the toolbar

## Backtesting Tips

- Use **Every tick based on real ticks** model for accurate results
- Test on at least 2–3 years of data
- Optimize `RSI_Oversold/Overbought` per pair (range: 30–40 / 60–70)
- Avoid over-optimizing — focus on robustness across multiple pairs

## Risk Warning

Past performance does not guarantee future results. Always test on a demo
account before trading live. Never risk more than you can afford to lose.
