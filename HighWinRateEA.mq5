//+------------------------------------------------------------------+
//|                                             HighWinRateEA.mq5    |
//|                         High Win Rate Expert Advisor             |
//|                   Strategy: RSI Mean Reversion + EMA Filter      |
//|                                                                  |
//|  Entry Filters:                                                  |
//|    - EMA(200): trend direction filter                            |
//|    - RSI(14): oversold/overbought cross signal                   |
//|    - Bollinger Bands(20,2): price at extremes                    |
//|    - Stochastic(5,3,3): momentum confirmation                    |
//|                                                                  |
//|  Exit Logic:                                                     |
//|    - SL  = 1.5 × ATR(14)                                        |
//|    - TP1 = 1.0 × ATR(14)  [close 50%]                           |
//|    - TP2 = 2.5 × ATR(14)  [close remainder]                     |
//|    - Trailing stop after TP1                                     |
//+------------------------------------------------------------------+
#property copyright   "High Win Rate EA"
#property version     "1.00"
#property description "RSI Mean Reversion EA with EMA Trend Filter, BB Confirmation, and ATR-based risk management"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include "HighWinRateEA.mqh"

//+------------------------------------------------------------------+
//|                      INPUT PARAMETERS                            |
//+------------------------------------------------------------------+

// --- Indicator Settings ---
input group              "=== Indicator Settings ==="
input int    RSI_Period       = 14;     // RSI period
input double RSI_OversoldLvl  = 30.0;  // RSI oversold level
input double RSI_OverboughtLvl= 70.0;  // RSI overbought level
input int    BB_Period        = 20;     // Bollinger Bands period
input double BB_Deviation     = 2.0;   // Bollinger Bands deviation
input int    EMA_Period       = 200;   // EMA trend filter period
input int    Stoch_K          = 5;     // Stochastic %K period
input int    Stoch_D          = 3;     // Stochastic %D period
input int    Stoch_Slowing    = 3;     // Stochastic slowing
input double Stoch_OversoldLvl  = 20.0; // Stochastic oversold level
input double Stoch_OverboughtLvl= 80.0; // Stochastic overbought level
input int    ATR_Period       = 14;    // ATR period

// --- Risk Management ---
input group              "=== Risk Management ==="
input double RiskPercent      = 1.0;   // Risk per trade (% of balance)
input double SL_ATR_Multi     = 1.5;   // Stop loss in ATR multiples
input double TP1_ATR_Multi    = 1.0;   // Take profit 1 in ATR multiples (50% close)
input double TP2_ATR_Multi    = 2.5;   // Take profit 2 in ATR multiples (full close)
input double Trail_ATR_Multi  = 1.0;   // Trailing stop in ATR multiples

// --- Session Filter ---
input group              "=== Session Filter ==="
input bool   UseSessionFilter = true;  // Enable session time filter
input int    LondonOpen       = 8;     // London session open (UTC hour)
input int    LondonClose      = 12;    // London session close (UTC hour)
input int    NYOpen           = 13;    // New York session open (UTC hour)
input int    NYClose          = 17;    // New York session close (UTC hour)

// --- Spread Filter ---
input group              "=== Spread Filter ==="
input int    MaxSpreadPoints  = 20;    // Maximum allowed spread (points)

// --- EA Settings ---
input group              "=== EA Settings ==="
input long   MagicNumber      = 202601; // EA magic number
input string TradeComment     = "HWR_EA"; // Order comment

//+------------------------------------------------------------------+
//|                    GLOBAL VARIABLES                              |
//+------------------------------------------------------------------+

// Indicator handles
int g_hRSI        = INVALID_HANDLE;
int g_hBB         = INVALID_HANDLE;
int g_hEMA        = INVALID_HANDLE;
int g_hStoch      = INVALID_HANDLE;
int g_hATR        = INVALID_HANDLE;

// Bar tracking
datetime g_lastBarTime = 0;

// Trade objects
CTrade         g_trade;
CPositionInfo  g_pos;

// Position tracking for partial close / trail
ulong    g_posTicket     = 0;
bool     g_tp1Hit        = false;
double   g_atrAtEntry    = 0.0;
double   g_trailLevel    = 0.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Validate inputs
   if(RiskPercent <= 0.0 || RiskPercent > 100.0)
     {
      Print("ERROR: RiskPercent must be between 0 and 100");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(SL_ATR_Multi <= 0.0 || TP1_ATR_Multi <= 0.0 || TP2_ATR_Multi <= 0.0)
     {
      Print("ERROR: ATR multipliers must be positive");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(TP1_ATR_Multi >= TP2_ATR_Multi)
     {
      Print("ERROR: TP1_ATR_Multi must be less than TP2_ATR_Multi");
      return INIT_PARAMETERS_INCORRECT;
     }

   // Create indicator handles
   g_hRSI   = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   g_hBB    = iBands(_Symbol, PERIOD_CURRENT, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   g_hEMA   = iMA(_Symbol, PERIOD_CURRENT, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   g_hStoch = iStochastic(_Symbol, PERIOD_CURRENT, Stoch_K, Stoch_D, Stoch_Slowing,
                           MODE_SMA, STO_LOWHIGH);
   g_hATR   = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);

   if(g_hRSI == INVALID_HANDLE || g_hBB == INVALID_HANDLE ||
      g_hEMA == INVALID_HANDLE || g_hStoch == INVALID_HANDLE ||
      g_hATR == INVALID_HANDLE)
     {
      Print("ERROR: Failed to create indicator handles");
      return INIT_FAILED;
     }

   // Configure trade object
   g_trade.SetExpertMagicNumber(MagicNumber);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   // Reset state
   g_posTicket  = 0;
   g_tp1Hit     = false;
   g_atrAtEntry = 0.0;
   g_trailLevel = 0.0;
   g_lastBarTime = 0;

   PrintFormat("HighWinRateEA v1.00 initialized on %s %s | Magic=%d",
               _Symbol, EnumToString(PERIOD_CURRENT), MagicNumber);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_hRSI   != INVALID_HANDLE) IndicatorRelease(g_hRSI);
   if(g_hBB    != INVALID_HANDLE) IndicatorRelease(g_hBB);
   if(g_hEMA   != INVALID_HANDLE) IndicatorRelease(g_hEMA);
   if(g_hStoch != INVALID_HANDLE) IndicatorRelease(g_hStoch);
   if(g_hATR   != INVALID_HANDLE) IndicatorRelease(g_hATR);

   Print("HighWinRateEA deinitialized. Reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Manage any open position on every tick (trailing stop, partial close)
   if(HasOpenPosition())
      ManageOpenPosition();

   // Only evaluate signals on new bar
   if(!IsNewBar())
      return;

   // Apply pre-trade filters
   if(HasOpenPosition()) return;
   if(!IsSpreadOK())     return;
   if(UseSessionFilter && !IsSessionActive()) return;

   // Evaluate signal
   TradeSignal sig = EvaluateSignal();
   if(sig == SIGNAL_BUY)
      OpenBuy();
   else if(sig == SIGNAL_SELL)
      OpenSell();
  }

//+------------------------------------------------------------------+
//| Evaluate trading signal                                          |
//+------------------------------------------------------------------+
TradeSignal EvaluateSignal()
  {
   // --- Read indicator buffers (last 3 bars) ---
   double rsi[], bbUpper[], bbLower[], bbMid[], ema[], stochK[], stochD[], atr[];

   ArraySetAsSeries(rsi,     true);
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbLower, true);
   ArraySetAsSeries(bbMid,   true);
   ArraySetAsSeries(ema,     true);
   ArraySetAsSeries(stochK,  true);
   ArraySetAsSeries(stochD,  true);
   ArraySetAsSeries(atr,     true);

   if(CopyBuffer(g_hRSI,   0, 0, 3, rsi)     < 3) return SIGNAL_NONE;
   if(CopyBuffer(g_hBB,    1, 0, 3, bbUpper)  < 3) return SIGNAL_NONE; // UPPER_BAND
   if(CopyBuffer(g_hBB,    2, 0, 3, bbLower)  < 3) return SIGNAL_NONE; // LOWER_BAND
   if(CopyBuffer(g_hBB,    0, 0, 3, bbMid)    < 3) return SIGNAL_NONE; // BASE_LINE
   if(CopyBuffer(g_hEMA,   0, 0, 3, ema)      < 3) return SIGNAL_NONE;
   if(CopyBuffer(g_hStoch, 0, 0, 3, stochK)   < 3) return SIGNAL_NONE; // MAIN_LINE
   if(CopyBuffer(g_hStoch, 1, 0, 3, stochD)   < 3) return SIGNAL_NONE; // SIGNAL_LINE
   if(CopyBuffer(g_hATR,   0, 0, 3, atr)      < 3) return SIGNAL_NONE;

   // Current completed bar (index 1) and previous (index 2)
   double closePrice = iClose(_Symbol, PERIOD_CURRENT, 1);
   double lowPrice   = iLow(_Symbol, PERIOD_CURRENT, 1);
   double highPrice  = iHigh(_Symbol, PERIOD_CURRENT, 1);

   // --- BUY Signal ---
   // 1. Price above EMA200 (uptrend)
   bool buyTrend    = (closePrice > ema[1]);
   // 2. RSI crossed above oversold (was below, now at/above)
   bool buyRSI      = (rsi[2] < RSI_OversoldLvl) && (rsi[1] >= RSI_OversoldLvl);
   // 3. Price touched lower Bollinger Band
   bool buyBB       = (lowPrice <= bbLower[1]);
   // 4. Stochastic %K crossed above %D from oversold zone
   bool buyStoch    = (stochK[2] < stochD[2]) && (stochK[1] >= stochD[1]) &&
                      (stochK[1] < Stoch_OversoldLvl + 10.0);

   if(buyTrend && buyRSI && buyBB && buyStoch)
      return SIGNAL_BUY;

   // --- SELL Signal ---
   // 1. Price below EMA200 (downtrend)
   bool sellTrend   = (closePrice < ema[1]);
   // 2. RSI crossed below overbought (was above, now at/below)
   bool sellRSI     = (rsi[2] > RSI_OverboughtLvl) && (rsi[1] <= RSI_OverboughtLvl);
   // 3. Price touched upper Bollinger Band
   bool sellBB      = (highPrice >= bbUpper[1]);
   // 4. Stochastic %K crossed below %D from overbought zone
   bool sellStoch   = (stochK[2] > stochD[2]) && (stochK[1] <= stochD[1]) &&
                      (stochK[1] > Stoch_OverboughtLvl - 10.0);

   if(sellTrend && sellRSI && sellBB && sellStoch)
      return SIGNAL_SELL;

   return SIGNAL_NONE;
  }

//+------------------------------------------------------------------+
//| Open a BUY position                                              |
//+------------------------------------------------------------------+
void OpenBuy()
  {
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_hATR, 0, 0, 2, atr) < 2) return;

   double currentATR = atr[1];
   if(currentATR <= 0.0) return;

   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double sl   = NormalizePrice(ask - SL_ATR_Multi  * currentATR, _Symbol);
   double tp2  = NormalizePrice(ask + TP2_ATR_Multi * currentATR, _Symbol);

   double slPoints = (ask - sl);
   double lots  = CalculateLotSize(_Symbol, slPoints, RiskPercent,
                                   AccountInfoDouble(ACCOUNT_BALANCE));
   if(lots <= 0.0)
     {
      Print("WARNING: Calculated lot size is 0, skipping BUY");
      return;
     }

   PrintTradeInfo("OPEN BUY", _Symbol, lots, ask, sl, tp2, TradeComment);

   if(g_trade.Buy(lots, _Symbol, ask, sl, tp2, TradeComment))
     {
      g_posTicket  = g_trade.ResultOrder();
      g_tp1Hit     = false;
      g_atrAtEntry = currentATR;
      g_trailLevel = 0.0;
      PrintFormat("BUY opened | Ticket=%d Lots=%.2f Ask=%.5f SL=%.5f TP=%.5f",
                  g_posTicket, lots, ask, sl, tp2);
     }
   else
      PrintFormat("BUY FAILED | Error=%d %s", g_trade.ResultRetcode(),
                  g_trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Open a SELL position                                             |
//+------------------------------------------------------------------+
void OpenSell()
  {
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_hATR, 0, 0, 2, atr) < 2) return;

   double currentATR = atr[1];
   if(currentATR <= 0.0) return;

   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl    = NormalizePrice(bid + SL_ATR_Multi  * currentATR, _Symbol);
   double tp2   = NormalizePrice(bid - TP2_ATR_Multi * currentATR, _Symbol);

   double slPoints = (sl - bid);
   double lots  = CalculateLotSize(_Symbol, slPoints, RiskPercent,
                                   AccountInfoDouble(ACCOUNT_BALANCE));
   if(lots <= 0.0)
     {
      Print("WARNING: Calculated lot size is 0, skipping SELL");
      return;
     }

   PrintTradeInfo("OPEN SELL", _Symbol, lots, bid, sl, tp2, TradeComment);

   if(g_trade.Sell(lots, _Symbol, bid, sl, tp2, TradeComment))
     {
      g_posTicket  = g_trade.ResultOrder();
      g_tp1Hit     = false;
      g_atrAtEntry = currentATR;
      g_trailLevel = 0.0;
      PrintFormat("SELL opened | Ticket=%d Lots=%.2f Bid=%.5f SL=%.5f TP=%.5f",
                  g_posTicket, lots, bid, sl, tp2);
     }
   else
      PrintFormat("SELL FAILED | Error=%d %s", g_trade.ResultRetcode(),
                  g_trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Manage open position: partial close at TP1, trailing stop        |
//+------------------------------------------------------------------+
void ManageOpenPosition()
  {
   if(g_posTicket == 0) return;
   if(!PositionSelectByTicket(g_posTicket)) return;

   long posType   = PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double curSL     = PositionGetDouble(POSITION_SL);
   double curTP     = PositionGetDouble(POSITION_TP);
   double lots      = PositionGetDouble(POSITION_VOLUME);
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double atr = g_atrAtEntry;
   if(atr <= 0.0) return;

   double tp1Level, currentPrice, newTrail;

   if(posType == POSITION_TYPE_BUY)
     {
      tp1Level     = NormalizePrice(openPrice + TP1_ATR_Multi * atr, _Symbol);
      currentPrice = bid;
      newTrail     = NormalizePrice(currentPrice - Trail_ATR_Multi * atr, _Symbol);

      // Check TP1 partial close
      if(!g_tp1Hit && currentPrice >= tp1Level)
        {
         double closeHalf = NormalizeLots(lots * 0.5, _Symbol);
         if(closeHalf >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
           {
            if(g_trade.PositionClosePartial(g_posTicket, closeHalf))
              {
               g_tp1Hit     = true;
               g_trailLevel = newTrail;
               PrintFormat("TP1 HIT BUY | Closed %.2f lots at %.5f", closeHalf, currentPrice);
              }
           }
        }

      // Trailing stop (after TP1 hit)
      if(g_tp1Hit && newTrail > curSL && newTrail < currentPrice)
        {
         if(g_trade.PositionModify(g_posTicket, newTrail, curTP))
           {
            g_trailLevel = newTrail;
            PrintFormat("TRAIL UPDATED BUY | New SL=%.5f", newTrail);
           }
        }
     }
   else if(posType == POSITION_TYPE_SELL)
     {
      tp1Level     = NormalizePrice(openPrice - TP1_ATR_Multi * atr, _Symbol);
      currentPrice = ask;
      newTrail     = NormalizePrice(currentPrice + Trail_ATR_Multi * atr, _Symbol);

      // Check TP1 partial close
      if(!g_tp1Hit && currentPrice <= tp1Level)
        {
         double closeHalf = NormalizeLots(lots * 0.5, _Symbol);
         if(closeHalf >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
           {
            if(g_trade.PositionClosePartial(g_posTicket, closeHalf))
              {
               g_tp1Hit     = true;
               g_trailLevel = newTrail;
               PrintFormat("TP1 HIT SELL | Closed %.2f lots at %.5f", closeHalf, currentPrice);
              }
           }
        }

      // Trailing stop (after TP1 hit)
      if(g_tp1Hit && newTrail < curSL && newTrail > currentPrice)
        {
         if(g_trade.PositionModify(g_posTicket, newTrail, curTP))
           {
            g_trailLevel = newTrail;
            PrintFormat("TRAIL UPDATED SELL | New SL=%.5f", newTrail);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check if a new bar has formed                                    |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime != g_lastBarTime)
     {
      g_lastBarTime = currentBarTime;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Check if current time is within active trading session           |
//+------------------------------------------------------------------+
bool IsSessionActive()
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int hour = dt.hour;

   bool londonSession = (hour >= LondonOpen && hour < LondonClose);
   bool nySession     = (hour >= NYOpen     && hour < NYClose);

   return (londonSession || nySession);
  }

//+------------------------------------------------------------------+
//| Check if current spread is within allowed limit                  |
//+------------------------------------------------------------------+
bool IsSpreadOK()
  {
   long spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spreadPoints > MaxSpreadPoints)
     {
      PrintFormat("Spread too high: %d > %d points, skipping signal",
                  spreadPoints, MaxSpreadPoints);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Check if EA has an open position on current symbol               |
//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   if(g_posTicket != 0)
     {
      if(PositionSelectByTicket(g_posTicket))
        {
         // Verify it's ours (magic + symbol)
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
        }
      // Position closed externally
      g_posTicket  = 0;
      g_tp1Hit     = false;
      g_atrAtEntry = 0.0;
      g_trailLevel = 0.0;
     }

   // Also scan all positions to recover state after EA restart
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         g_posTicket = PositionGetInteger(POSITION_TICKET);
         return true;
        }
     }
   return false;
  }
//+------------------------------------------------------------------+
