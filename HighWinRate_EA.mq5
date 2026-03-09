//+------------------------------------------------------------------+
//|                                             HighWinRate_EA.mq5   |
//|                                         traderfund90-debug       |
//|                    High Win Rate EA - Multi-Filter Confirmation   |
//+------------------------------------------------------------------+
#property copyright "traderfund90-debug"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade   trade;
CPositionInfo posInfo;

//--- Input Parameters
input group "=== TRADE SETTINGS ==="
input double RiskPercent    = 1.0;    // Risk % per trade
input double RR_Ratio       = 2.0;    // Risk:Reward Ratio (TP = RR * SL)
input int    MagicNumber    = 202600; // Magic Number
input int    MaxOpenTrades  = 1;      // Max open trades at once

input group "=== TREND FILTER ==="
input int    EMA_Fast       = 21;     // Fast EMA period
input int    EMA_Slow       = 50;     // Slow EMA period
input int    EMA_Trend      = 200;    // Trend EMA period

input group "=== RSI SETTINGS ==="
input int    RSI_Period     = 14;     // RSI period
input double RSI_OB         = 60.0;  // RSI overbought threshold (buy above)
input double RSI_OS         = 40.0;  // RSI oversold threshold (sell below)

input group "=== ATR SETTINGS ==="
input int    ATR_Period     = 14;     // ATR period
input double ATR_Multiplier = 1.5;    // ATR multiplier for SL

input group "=== SESSION FILTER ==="
input bool   UseLondonSession  = true;  // Trade London session (08:00-17:00 GMT)
input bool   UseNewYorkSession = true;  // Trade New York session (13:00-22:00 GMT)

//--- Global variables
int emaFastHandle, emaSlowHandle, emaTrendHandle, rsiHandle, atrHandle;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);

   emaFastHandle  = iMA(_Symbol, PERIOD_H1, EMA_Fast,  0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle  = iMA(_Symbol, PERIOD_H1, EMA_Slow,  0, MODE_EMA, PRICE_CLOSE);
   emaTrendHandle = iMA(_Symbol, PERIOD_H1, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle      = iRSI(_Symbol, PERIOD_H1, RSI_Period, PRICE_CLOSE);
   atrHandle      = iATR(_Symbol, PERIOD_H1, ATR_Period);

   if(emaFastHandle == INVALID_HANDLE || emaSlowHandle == INVALID_HANDLE ||
      emaTrendHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return INIT_FAILED;
   }

   Print("HighWinRate EA initialized on ", _Symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(emaFastHandle);
   IndicatorRelease(emaSlowHandle);
   IndicatorRelease(emaTrendHandle);
   IndicatorRelease(rsiHandle);
   IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only process on new H1 bar
   datetime currentBar = iTime(_Symbol, PERIOD_H1, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;

   // Session filter
   if(!IsValidSession()) return;

   // Count open positions
   if(CountOpenPositions() >= MaxOpenTrades) return;

   // Get indicator values
   double emaFast[3], emaSlow[3], emaTrend[3], rsi[3], atr[3];

   if(CopyBuffer(emaFastHandle,  0, 1, 3, emaFast)  < 3) return;
   if(CopyBuffer(emaSlowHandle,  0, 1, 3, emaSlow)  < 3) return;
   if(CopyBuffer(emaTrendHandle, 0, 1, 3, emaTrend) < 3) return;
   if(CopyBuffer(rsiHandle,      0, 1, 3, rsi)      < 3) return;
   if(CopyBuffer(atrHandle,      0, 1, 3, atr)      < 3) return;

   double fastNow  = emaFast[2],  fastPrev  = emaFast[1];
   double slowNow  = emaSlow[2],  slowPrev  = emaSlow[1];
   double trendNow = emaTrend[2];
   double rsiNow   = rsi[2];
   double atrNow   = atr[2];

   // EMA crossover detection
   bool bullCross = (fastPrev < slowPrev) && (fastNow > slowNow);
   bool bearCross = (fastPrev > slowPrev) && (fastNow < slowNow);

   // Price above/below trend EMA
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   bool aboveTrend = ask > trendNow;
   bool belowTrend = bid < trendNow;

   // BUY Signal: Bullish EMA cross + price above 200 EMA + RSI above 50
   if(bullCross && aboveTrend && rsiNow > RSI_OB)
   {
      double sl = ask - (atrNow * ATR_Multiplier);
      double tp = ask + (atrNow * ATR_Multiplier * RR_Ratio);
      double lots = CalculateLotSize(ask - sl);
      if(lots > 0)
      {
         trade.Buy(lots, _Symbol, ask, sl, tp, "HWR_Buy");
         Print("BUY signal: RSI=", DoubleToString(rsiNow, 2),
               " ATR=", DoubleToString(atrNow, 5),
               " Lots=", DoubleToString(lots, 2));
      }
   }

   // SELL Signal: Bearish EMA cross + price below 200 EMA + RSI below 50
   if(bearCross && belowTrend && rsiNow < RSI_OS)
   {
      double sl = bid + (atrNow * ATR_Multiplier);
      double tp = bid - (atrNow * ATR_Multiplier * RR_Ratio);
      double lots = CalculateLotSize(sl - bid);
      if(lots > 0)
      {
         trade.Sell(lots, _Symbol, bid, sl, tp, "HWR_Sell");
         Print("SELL signal: RSI=", DoubleToString(rsiNow, 2),
               " ATR=", DoubleToString(atrNow, 5),
               " Lots=", DoubleToString(lots, 2));
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk %                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints)
{
   if(slPoints <= 0) return 0;

   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount     = accountBalance * RiskPercent / 100.0;
   double tickValue      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize       = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep        = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot         = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot         = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(tickValue == 0 || tickSize == 0) return 0;

   double valuePerLot = (slPoints / tickSize) * tickValue;
   if(valuePerLot <= 0) return 0;

   double lots = riskAmount / valuePerLot;
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   return lots;
}

//+------------------------------------------------------------------+
//| Count open positions for this EA                                 |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == MagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Session filter - GMT time check                                  |
//+------------------------------------------------------------------+
bool IsValidSession()
{
   MqlDateTime tm;
   TimeToStruct(TimeGMT(), tm);
   int hour = tm.hour;

   bool london  = UseLondonSession  && (hour >= 8  && hour < 17);
   bool newyork = UseNewYorkSession && (hour >= 13 && hour < 22);

   return (london || newyork);
}
//+------------------------------------------------------------------+
