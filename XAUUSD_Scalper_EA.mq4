//+------------------------------------------------------------------+
//|                                           XAUUSD_Scalper_EA.mq4  |
//|                                         traderfund90-debug        |
//|              XAUUSD High Win Rate Scalper - M5/M15               |
//|  Strategy: EMA trend + BB pullback + RSI + Stoch confluence      |
//+------------------------------------------------------------------+
#property copyright "traderfund90-debug"
#property version   "1.00"
#property strict

//--- Timeframe
extern ENUM_TIMEFRAMES ScalpTF         = PERIOD_M5;   // Scalp chart TF
extern ENUM_TIMEFRAMES TrendTF         = PERIOD_H1;   // Trend filter TF

//--- Trade Management
extern double RiskPercent              = 1.0;         // Risk % per trade
extern double RR_Ratio                 = 1.5;         // Risk:Reward (TP = SL x this)
extern bool   UseTrailingStop          = true;        // Trail SL once in profit
extern double TrailATRMultiplier       = 0.8;         // Trail distance in ATR units
extern double TrailActivateRR          = 0.5;         // Activate trail at this RR reached
extern int    MagicNumber              = 303700;
extern int    MaxOpenTrades            = 2;
extern int    MaxTradesPerDay          = 6;           // Daily cap
extern int    Slippage                 = 5;           // Gold needs a bit more

//--- Spread Filter (Gold spread can spike)
extern double MaxSpreadPoints          = 30.0;        // Skip trade if spread > this (in points)

//--- EMA Settings
extern int    EMA_Fast                 = 8;           // Fast EMA (scalp)
extern int    EMA_Mid                  = 21;          // Mid EMA (signal zone)
extern int    EMA_Trend                = 200;         // Trend filter

//--- Bollinger Bands
extern int    BB_Period                = 20;
extern double BB_Deviation             = 2.0;

//--- RSI
extern int    RSI_Period               = 7;           // Short RSI for scalping
extern double RSI_BuyMax               = 55.0;        // BUY: RSI must be below this (not overbought)
extern double RSI_SellMin              = 45.0;        // SELL: RSI must be above this (not oversold)

//--- Stochastic
extern int    Stoch_K                  = 5;
extern int    Stoch_D                  = 3;
extern int    Stoch_Slowing            = 3;
extern double Stoch_OB                 = 75.0;        // Overbought
extern double Stoch_OS                 = 25.0;        // Oversold

//--- ATR
extern int    ATR_Period               = 14;
extern double ATR_SL_Multiplier        = 1.0;         // Tight SL for scalping

//--- Session Filter (GMT)
extern bool   UseLondonOpen            = true;        // 07:00-10:00 GMT (Gold loves this)
extern bool   UseLondonNYOverlap       = true;        // 13:00-17:00 GMT (most volatile)
extern bool   UseAsianSession          = false;       // 00:00-07:00 GMT (slower for Gold)

//--- Candle Pattern Filter
extern bool   RequirePinBar            = false;       // Require pin bar / rejection candle
extern double PinBarRatio              = 2.0;         // Wick must be PinBarRatio x body

//--- State
datetime lastBarTime   = 0;
int      tradesToday   = 0;
datetime lastTradeDay  = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(Symbol() != "XAUUSD" && Symbol() != "GOLD" &&
      StringFind(Symbol(), "XAU") < 0)
      Print("WARNING: This EA is optimised for XAUUSD. Current symbol: ", Symbol());

   Print("XAUUSD Scalper v1.00 | TF=", EnumToString(ScalpTF),
         " TrendTF=", EnumToString(TrendTF),
         " RR=", DoubleToStr(RR_Ratio,1),
         " MaxSpread=", DoubleToStr(MaxSpreadPoints,0));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
void OnTick()
{
   // --- New bar guard
   datetime currentBar = iTime(Symbol(), ScalpTF, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;

   // --- Reset daily trade counter
   ResetDailyCounter();

   // --- Guards
   if(!IsValidSession())        return;
   if(tradesToday >= MaxTradesPerDay) return;
   if(CountOpenOrders() >= MaxOpenTrades) return;

   // --- Spread filter
   double spreadPoints = (Ask - Bid) / Point;
   if(spreadPoints > MaxSpreadPoints)
   {
      Print("Spread too wide: ", DoubleToStr(spreadPoints,1), " pts - skipping");
      return;
   }

   // ==============================================================
   // INDICATOR VALUES (last closed bar = index 1)
   // ==============================================================

   // Scalp TF
   double fastNow    = iMA(Symbol(), ScalpTF, EMA_Fast,  0, MODE_EMA, PRICE_CLOSE, 1);
   double fastPrev   = iMA(Symbol(), ScalpTF, EMA_Fast,  0, MODE_EMA, PRICE_CLOSE, 2);
   double midNow     = iMA(Symbol(), ScalpTF, EMA_Mid,   0, MODE_EMA, PRICE_CLOSE, 1);

   double bbUpper    = iBands(Symbol(), ScalpTF, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double bbLower    = iBands(Symbol(), ScalpTF, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double bbMid      = iBands(Symbol(), ScalpTF, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_MAIN,  1);

   double rsiNow     = iRSI(Symbol(), ScalpTF, RSI_Period, PRICE_CLOSE, 1);
   double stochMain  = iStochastic(Symbol(), ScalpTF, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, 0, MODE_MAIN,   1);
   double stochSig   = iStochastic(Symbol(), ScalpTF, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, 0, MODE_SIGNAL, 1);
   double stochPrev  = iStochastic(Symbol(), ScalpTF, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, 0, MODE_MAIN,   2);
   double stochSigPrev = iStochastic(Symbol(), ScalpTF, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, 0, MODE_SIGNAL, 2);
   double atrNow     = iATR(Symbol(), ScalpTF, ATR_Period, 1);

   double closeNow   = iClose(Symbol(), ScalpTF, 1);
   double openNow    = iOpen (Symbol(), ScalpTF, 1);
   double highNow    = iHigh (Symbol(), ScalpTF, 1);
   double lowNow     = iLow  (Symbol(), ScalpTF, 1);

   // Trend TF
   double trendEMA   = iMA(Symbol(), TrendTF, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE, 1);
   double trendClose = iClose(Symbol(), TrendTF, 1);

   double ask = Ask;
   double bid = Bid;

   // ==============================================================
   // TREND FILTER
   // ==============================================================
   bool bullTrend = (trendClose > trendEMA);
   bool bearTrend = (trendClose < trendEMA);

   // ==============================================================
   // SIGNAL CONDITIONS
   // ==============================================================

   // --- BUY conditions
   // 1. Bullish trend on higher TF
   // 2. Price pulled back to or below mid EMA (value zone)
   // 3. BB: close above lower band (bounce, not breakdown)
   // 4. RSI: not overbought (room to move up)
   // 5. Stochastic: crossed up from oversold
   // 6. Fast EMA started turning up (fastNow > fastPrev)
   bool buyPullback  = (closeNow <= midNow * 1.0005);      // at or below mid EMA (+0.05% buffer for Gold)
   bool buyBB        = (lowNow  <= bbLower * 1.001) &&     // touched lower band
                       (closeNow > bbLower);                // closed back above
   bool buyRSI       = (rsiNow < RSI_BuyMax);
   bool buyStoch     = (stochPrev < stochSigPrev) &&        // stoch crossed up
                       (stochMain > stochSig)  &&
                       (stochMain < Stoch_OB);              // not already OB
   bool buyEMA       = (fastNow > fastPrev);                // EMA turning up
   bool buyPin       = !RequirePinBar || IsBullishPin(openNow, highNow, lowNow, closeNow);

   bool buySignal = bullTrend && buyPullback && buyBB && buyRSI && buyStoch && buyEMA && buyPin;

   // --- SELL conditions
   // 1. Bearish trend on higher TF
   // 2. Price pulled back up to or above mid EMA
   // 3. BB: close below upper band (rejection, not breakout)
   // 4. RSI: not oversold
   // 5. Stochastic: crossed down from overbought
   // 6. Fast EMA turning down
   bool sellPullback = (closeNow >= midNow * 0.9995);
   bool sellBB       = (highNow >= bbUpper * 0.999) &&
                       (closeNow < bbUpper);
   bool sellRSI      = (rsiNow > RSI_SellMin);
   bool sellStoch    = (stochPrev > stochSigPrev) &&        // stoch crossed down
                       (stochMain < stochSig) &&
                       (stochMain > Stoch_OS);              // not already OS
   bool sellEMA      = (fastNow < fastPrev);
   bool sellPin      = !RequirePinBar || IsBearishPin(openNow, highNow, lowNow, closeNow);

   bool sellSignal = bearTrend && sellPullback && sellBB && sellRSI && sellStoch && sellEMA && sellPin;

   // ==============================================================
   // EXECUTE TRADES
   // ==============================================================
   if(buySignal)
   {
      double sl   = NormalizeDouble(ask - atrNow * ATR_SL_Multiplier, Digits);
      double dist = ask - sl;
      double tp   = NormalizeDouble(ask + dist * RR_Ratio, Digits);
      double lots = CalculateLotSize(dist);

      if(lots > 0)
      {
         int ticket = OrderSend(Symbol(), OP_BUY, lots, ask, Slippage, sl, tp,
                                "XAU_Scalp_Buy", MagicNumber, 0, clrDodgerBlue);
         if(ticket < 0)
            Print("BUY failed, error: ", GetLastError());
         else
         {
            tradesToday++;
            Print("BUY | Price=", DoubleToStr(ask,2),
                  " SL=", DoubleToStr(sl,2),
                  " TP=", DoubleToStr(tp,2),
                  " Lots=", DoubleToStr(lots,2),
                  " RSI=", DoubleToStr(rsiNow,1),
                  " Stoch=", DoubleToStr(stochMain,1));
         }
      }
   }

   if(sellSignal)
   {
      double sl   = NormalizeDouble(bid + atrNow * ATR_SL_Multiplier, Digits);
      double dist = sl - bid;
      double tp   = NormalizeDouble(bid - dist * RR_Ratio, Digits);
      double lots = CalculateLotSize(dist);

      if(lots > 0)
      {
         int ticket = OrderSend(Symbol(), OP_SELL, lots, bid, Slippage, sl, tp,
                                "XAU_Scalp_Sell", MagicNumber, 0, clrOrangeRed);
         if(ticket < 0)
            Print("SELL failed, error: ", GetLastError());
         else
         {
            tradesToday++;
            Print("SELL | Price=", DoubleToStr(bid,2),
                  " SL=", DoubleToStr(sl,2),
                  " TP=", DoubleToStr(tp,2),
                  " Lots=", DoubleToStr(lots,2),
                  " RSI=", DoubleToStr(rsiNow,1),
                  " Stoch=", DoubleToStr(stochMain,1));
         }
      }
   }

   // ==============================================================
   // TRAILING STOP MANAGER
   // ==============================================================
   if(UseTrailingStop)
      ManageTrailingStop(atrNow);
}

//+------------------------------------------------------------------+
//| Trailing stop - activate at TrailActivateRR, trail by ATR       |
//+------------------------------------------------------------------+
void ManageTrailingStop(double atrNow)
{
   double trailDist = atrNow * TrailATRMultiplier;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol())                   continue;
      if(OrderMagicNumber() != MagicNumber)           continue;

      double openPrice = OrderOpenPrice();
      double curSL     = OrderStopLoss();
      double initDist  = MathAbs(OrderTakeProfit() - openPrice) / RR_Ratio; // original SL dist

      if(OrderType() == OP_BUY)
      {
         double activateAt = openPrice + initDist * TrailActivateRR;
         if(Bid < activateAt) continue; // not activated yet

         double newSL = NormalizeDouble(Bid - trailDist, Digits);
         if(newSL > curSL + Point)
            OrderModify(OrderTicket(), openPrice, newSL, OrderTakeProfit(), 0, clrDodgerBlue);
      }
      else if(OrderType() == OP_SELL)
      {
         double activateAt = openPrice - initDist * TrailActivateRR;
         if(Ask > activateAt) continue;

         double newSL = NormalizeDouble(Ask + trailDist, Digits);
         if(newSL < curSL - Point || curSL == 0)
            OrderModify(OrderTicket(), openPrice, newSL, OrderTakeProfit(), 0, clrOrangeRed);
      }
   }
}

//+------------------------------------------------------------------+
//| Pin bar detection                                                |
//+------------------------------------------------------------------+
bool IsBullishPin(double open, double high, double low, double close)
{
   double body      = MathAbs(close - open);
   double lowerWick = MathMin(open, close) - low;
   double upperWick = high - MathMax(open, close);
   if(body == 0) return false;
   return (lowerWick >= body * PinBarRatio) && (upperWick < lowerWick * 0.5);
}

bool IsBearishPin(double open, double high, double low, double close)
{
   double body      = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   if(body == 0) return false;
   return (upperWick >= body * PinBarRatio) && (lowerWick < upperWick * 0.5);
}

//+------------------------------------------------------------------+
//| Lot sizing                                                        |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDist)
{
   if(slDist <= 0) return 0;

   double balance    = AccountBalance();
   double riskAmt    = balance * RiskPercent / 100.0;
   double tickValue  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize   = MarketInfo(Symbol(), MODE_TICKSIZE);
   double lotStep    = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot     = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot     = MarketInfo(Symbol(), MODE_MAXLOT);

   if(balance <= 0 || tickValue == 0 || tickSize == 0) return 0;

   double valuePerLot = (slDist / tickSize) * tickValue;
   if(valuePerLot <= 0) return 0;

   double lots = MathFloor((riskAmt / valuePerLot) / lotStep) * lotStep;
   if(lots < minLot) return 0;

   lots = MathMin(maxLot, lots);
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Count open orders                                                 |
//+------------------------------------------------------------------+
int CountOpenOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
            count++;
   return count;
}

//+------------------------------------------------------------------+
//| Daily trade counter reset                                         |
//+------------------------------------------------------------------+
void ResetDailyCounter()
{
   datetime today = iTime(Symbol(), PERIOD_D1, 0);
   if(today != lastTradeDay)
   {
      tradesToday  = 0;
      lastTradeDay = today;
   }
}

//+------------------------------------------------------------------+
//| Session filter (GMT)                                              |
//+------------------------------------------------------------------+
bool IsValidSession()
{
   int hour = TimeHour(TimeGMT());

   bool londonOpen   = UseLondonOpen       && (hour >= 7  && hour < 10);
   bool londonNY     = UseLondonNYOverlap  && (hour >= 13 && hour < 17);
   bool asian        = UseAsianSession     && (hour >= 0  && hour < 7);

   return (londonOpen || londonNY || asian);
}
//+------------------------------------------------------------------+
