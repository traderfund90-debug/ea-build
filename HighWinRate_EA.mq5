//+------------------------------------------------------------------+
//|                                             HighWinRate_EA.mq5   |
//|                          High Win-Rate Expert Advisor for MT5     |
//|                                                                    |
//| Strategy: Multi-indicator confluence trading                       |
//|  - EMA trend filter (fast/slow cross)                             |
//|  - RSI for overbought/oversold entry timing                       |
//|  - Bollinger Bands for price extreme confirmation                 |
//|  - ATR-based adaptive stop-loss & take-profit                    |
//|  - Session filter (London + New York only)                        |
//|  - Trailing stop for profit protection                            |
//+------------------------------------------------------------------+
#property copyright "HighWinRate EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input Parameters
input group "=== Trend Filter ==="
input int    FastEMA_Period    = 21;       // Fast EMA Period
input int    SlowEMA_Period    = 50;       // Slow EMA Period
input int    TrendEMA_Period   = 200;      // Trend EMA Period

input group "=== RSI Settings ==="
input int    RSI_Period        = 14;       // RSI Period
input double RSI_Oversold      = 35.0;     // RSI Oversold Level (Buy)
input double RSI_Overbought    = 65.0;     // RSI Overbought Level (Sell)

input group "=== Bollinger Bands ==="
input int    BB_Period         = 20;       // BB Period
input double BB_Deviation      = 2.0;      // BB Standard Deviation

input group "=== Risk Management ==="
input double RiskPercent       = 1.0;      // Risk % per trade
input double ATR_SL_Multi      = 1.5;      // ATR multiplier for Stop Loss
input double ATR_TP_Multi      = 1.0;      // ATR multiplier for Take Profit (tight = high WR)
input int    ATR_Period        = 14;       // ATR Period
input bool   UseTrailingStop   = true;     // Enable Trailing Stop
input double TrailATRMulti     = 1.0;      // Trailing Stop ATR multiplier

input group "=== Session Filter ==="
input bool   UseSessionFilter  = true;     // Enable session filter
input int    SessionStartHour  = 7;        // Session Start Hour (Server Time)
input int    SessionEndHour    = 20;       // Session End Hour (Server Time)

input group "=== Trade Settings ==="
input int    MagicNumber       = 202401;   // Magic Number
input int    MaxOpenTrades     = 2;        // Max simultaneous open trades
input int    MinBarsBetweenTrades = 3;     // Min bars between new trades
input bool   CloseOppositeSignal = true;   // Close trade on opposite signal

//--- Global Variables
CTrade         trade;
CPositionInfo  posInfo;

int    handleFastEMA, handleSlowEMA, handleTrendEMA;
int    handleRSI, handleBB, handleATR;
double fastEMA[], slowEMA[], trendEMA[];
double rsiVal[], bbUpper[], bbLower[], bbMiddle[];
double atrVal[];
datetime lastBarTime = 0;
int    barsSinceLastTrade = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   //--- Create indicator handles
   handleFastEMA  = iMA(_Symbol, PERIOD_CURRENT, FastEMA_Period,  0, MODE_EMA, PRICE_CLOSE);
   handleSlowEMA  = iMA(_Symbol, PERIOD_CURRENT, SlowEMA_Period,  0, MODE_EMA, PRICE_CLOSE);
   handleTrendEMA = iMA(_Symbol, PERIOD_CURRENT, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI      = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   handleBB       = iBands(_Symbol, PERIOD_CURRENT, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   handleATR      = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);

   if(handleFastEMA == INVALID_HANDLE || handleSlowEMA == INVALID_HANDLE ||
      handleTrendEMA == INVALID_HANDLE || handleRSI == INVALID_HANDLE ||
      handleBB == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles");
      return INIT_FAILED;
   }

   ArraySetAsSeries(fastEMA,  true);
   ArraySetAsSeries(slowEMA,  true);
   ArraySetAsSeries(trendEMA, true);
   ArraySetAsSeries(rsiVal,   true);
   ArraySetAsSeries(bbUpper,  true);
   ArraySetAsSeries(bbLower,  true);
   ArraySetAsSeries(bbMiddle, true);
   ArraySetAsSeries(atrVal,   true);

   Print("HighWinRate EA initialized successfully on ", _Symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleFastEMA);
   IndicatorRelease(handleSlowEMA);
   IndicatorRelease(handleTrendEMA);
   IndicatorRelease(handleRSI);
   IndicatorRelease(handleBB);
   IndicatorRelease(handleATR);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Only process on new bar
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime)
   {
      //--- Still manage trailing stop intra-bar
      if(UseTrailingStop) ManageTrailingStop();
      return;
   }
   lastBarTime = currentBarTime;
   barsSinceLastTrade++;

   //--- Refresh indicator data
   if(!RefreshIndicators()) return;

   //--- Session filter
   if(UseSessionFilter && !IsSessionActive()) return;

   //--- Check for close on opposite signal (before checking entries)
   if(CloseOppositeSignal) CheckCloseOnOpposite();

   //--- Entry logic
   if(CountOpenTrades() < MaxOpenTrades && barsSinceLastTrade >= MinBarsBetweenTrades)
   {
      int signal = GetSignal();
      if(signal == 1)  OpenBuy();
      if(signal == -1) OpenSell();
   }
}

//+------------------------------------------------------------------+
//| Refresh all indicator buffers                                     |
//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   if(CopyBuffer(handleFastEMA,  0, 0, 3, fastEMA)  < 3) return false;
   if(CopyBuffer(handleSlowEMA,  0, 0, 3, slowEMA)  < 3) return false;
   if(CopyBuffer(handleTrendEMA, 0, 0, 3, trendEMA) < 3) return false;
   if(CopyBuffer(handleRSI,      0, 0, 3, rsiVal)   < 3) return false;
   if(CopyBuffer(handleBB, UPPER_BAND,  0, 3, bbUpper)  < 3) return false;
   if(CopyBuffer(handleBB, LOWER_BAND,  0, 3, bbLower)  < 3) return false;
   if(CopyBuffer(handleBB, BASE_LINE,   0, 3, bbMiddle) < 3) return false;
   if(CopyBuffer(handleATR, 0, 0, 3, atrVal) < 3) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Get trade signal: 1=Buy, -1=Sell, 0=No signal                   |
//+------------------------------------------------------------------+
int GetSignal()
{
   double closePrice = iClose(_Symbol, PERIOD_CURRENT, 1);
   double atr        = atrVal[1];

   //--- Trend direction: price must be above/below 200 EMA
   bool bullTrend = (closePrice > trendEMA[1]);
   bool bearTrend = (closePrice < trendEMA[1]);

   //--- EMA alignment: fast above slow for bull, fast below slow for bear
   bool emaAlignedBull = (fastEMA[1] > slowEMA[1]);
   bool emaAlignedBear = (fastEMA[1] < slowEMA[1]);

   //--- RSI confirmation
   bool rsiBuyZone  = (rsiVal[1] < RSI_Oversold);
   bool rsiSellZone = (rsiVal[1] > RSI_Overbought);

   //--- Bollinger Band touch (price near lower/upper band)
   bool bbBuyTouch  = (closePrice <= bbLower[1] + atr * 0.3);
   bool bbSellTouch = (closePrice >= bbUpper[1] - atr * 0.3);

   //--- EMA crossover confirmation (fast crossed above/below slow on last bar)
   bool emaCrossedBull = (fastEMA[1] > slowEMA[1] && fastEMA[2] <= slowEMA[2]);
   bool emaCrossedBear = (fastEMA[1] < slowEMA[1] && fastEMA[2] >= slowEMA[2]);

   //--- BUY signal: trend up + EMA aligned + RSI oversold + BB lower touch
   bool buySignal  = bullTrend && emaAlignedBull && rsiBuyZone  && bbBuyTouch;
   //--- SELL signal: trend down + EMA aligned + RSI overbought + BB upper touch
   bool sellSignal = bearTrend && emaAlignedBear && rsiSellZone && bbSellTouch;

   //--- Secondary trigger: EMA crossover in trend direction
   if(!buySignal  && bullTrend && emaCrossedBull && rsiVal[1] < 55) buySignal  = true;
   if(!sellSignal && bearTrend && emaCrossedBear && rsiVal[1] > 45) sellSignal = true;

   if(buySignal)  return 1;
   if(sellSignal) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Open Buy trade                                                    |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = atrVal[1];
   double sl  = ask - atr * ATR_SL_Multi;
   double tp  = ask + atr * ATR_TP_Multi;

   //--- Normalize prices
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   double lotSize = CalculateLotSize(MathAbs(ask - sl));
   if(lotSize <= 0) return;

   if(trade.Buy(lotSize, _Symbol, ask, sl, tp, "HighWR_Buy"))
   {
      Print("BUY opened: Lot=", lotSize, " SL=", sl, " TP=", tp);
      barsSinceLastTrade = 0;
   }
}

//+------------------------------------------------------------------+
//| Open Sell trade                                                   |
//+------------------------------------------------------------------+
void OpenSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double atr = atrVal[1];
   double sl  = bid + atr * ATR_SL_Multi;
   double tp  = bid - atr * ATR_TP_Multi;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   double lotSize = CalculateLotSize(MathAbs(sl - bid));
   if(lotSize <= 0) return;

   if(trade.Sell(lotSize, _Symbol, bid, sl, tp, "HighWR_Sell"))
   {
      Print("SELL opened: Lot=", lotSize, " SL=", sl, " TP=", tp);
      barsSinceLastTrade = 0;
   }
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk %                          |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice)
{
   if(slDistancePrice <= 0) return 0;

   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount     = accountBalance * RiskPercent / 100.0;
   double tickValue      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize       = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep        = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot         = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot         = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   double valuePerLotPerPoint = tickValue / tickSize;
   double lotSize = riskAmount / (slDistancePrice * valuePerLotPerPoint);

   //--- Round to lot step
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Manage trailing stop for open positions                           |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(CopyBuffer(handleATR, 0, 0, 2, atrVal) < 2) return;
   double atr = atrVal[0];

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != MagicNumber) continue;

      double newSL    = 0;
      double currentSL = posInfo.StopLoss();
      double openPrice = posInfo.PriceOpen();
      double trailDist = atr * TrailATRMulti;

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         newSL = bid - trailDist;
         if(newSL > currentSL && newSL > openPrice) // Only trail in profit
            trade.PositionModify(posInfo.Ticket(), NormalizeDouble(newSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), posInfo.TakeProfit());
      }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         newSL = ask + trailDist;
         if((newSL < currentSL || currentSL == 0) && newSL < openPrice) // Only trail in profit
            trade.PositionModify(posInfo.Ticket(), NormalizeDouble(newSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), posInfo.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
//| Close position if opposite signal appears                         |
//+------------------------------------------------------------------+
void CheckCloseOnOpposite()
{
   int signal = GetSignal();
   if(signal == 0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != MagicNumber) continue;

      if(signal == 1  && posInfo.PositionType() == POSITION_TYPE_SELL)
         trade.PositionClose(posInfo.Ticket());
      if(signal == -1 && posInfo.PositionType() == POSITION_TYPE_BUY)
         trade.PositionClose(posInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Count open trades for this EA                                     |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() == _Symbol && posInfo.Magic() == MagicNumber)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check if current time is within trading session                   |
//+------------------------------------------------------------------+
bool IsSessionActive()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   return (hour >= SessionStartHour && hour < SessionEndHour);
}
//+------------------------------------------------------------------+
