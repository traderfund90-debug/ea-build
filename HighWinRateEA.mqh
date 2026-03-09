//+------------------------------------------------------------------+
//|                                             HighWinRateEA.mqh    |
//|                        High Win Rate EA - Helper Definitions     |
//|                   Strategy: RSI Mean Reversion + EMA Filter      |
//+------------------------------------------------------------------+
#pragma once

//--- Trade signal enumeration
enum TradeSignal
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
  };

//--- Position state tracking
struct PositionState
  {
   ulong             ticket;
   bool              tp1Hit;
   double            trailStopLevel;
   double            atrAtEntry;
  };

//+------------------------------------------------------------------+
//| Normalize lot size to broker specifications                      |
//+------------------------------------------------------------------+
double NormalizeLots(double lots, const string symbol)
  {
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(lotStep <= 0.0) lotStep = 0.01;
   lots = MathRound(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   int digits = (int)MathRound(-MathLog(lotStep) / MathLog(10.0));
   if(digits < 0) digits = 0;

   return NormalizeDouble(lots, digits);
  }

//+------------------------------------------------------------------+
//| Normalize price to symbol point specification                    |
//+------------------------------------------------------------------+
double NormalizePrice(double price, const string symbol)
  {
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
  }

//+------------------------------------------------------------------+
//| Print trade information to journal                               |
//+------------------------------------------------------------------+
void PrintTradeInfo(const string action, const string symbol,
                    double lots, double price, double sl, double tp,
                    const string comment = "")
  {
   PrintFormat("[%s] %s | Lots=%.2f Price=%.5f SL=%.5f TP=%.5f %s",
               action, symbol, lots, price, sl, tp, comment);
  }

//+------------------------------------------------------------------+
//| Calculate risk-based lot size                                    |
//+------------------------------------------------------------------+
double CalculateLotSize(const string symbol, double slPoints,
                        double riskPercent, double accountBalance)
  {
   if(slPoints <= 0.0) return 0.0;

   double tickValue  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double pointSize  = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(tickValue <= 0.0 || tickSize <= 0.0 || pointSize <= 0.0) return 0.0;

   double riskAmount    = accountBalance * riskPercent / 100.0;
   double ticksInSL     = slPoints / tickSize;
   double lossPerLot    = ticksInSL * tickValue;

   if(lossPerLot <= 0.0) return 0.0;

   double lots = riskAmount / lossPerLot;
   return NormalizeLots(lots, symbol);
  }
//+------------------------------------------------------------------+
