//+------------------------------------------------------------------+
//|                                             HighWinRate_EA.mq4   |
//|                                         traderfund90-debug       |
//|                    High Win Rate EA - Multi-Filter + Retest      |
//+------------------------------------------------------------------+
#property copyright "traderfund90-debug"
#property version   "1.10"
#property strict

//--- Input Parameters
extern double RiskPercent          = 1.0;   // Risk % per trade
extern double RR_Ratio             = 2.0;   // Risk:Reward Ratio
extern int    MagicNumber          = 202600;
extern int    MaxOpenTrades        = 1;
extern int    Slippage             = 3;

extern int    EMA_Fast             = 21;
extern int    EMA_Slow             = 50;
extern int    EMA_Trend            = 200;

extern int    RSI_Period           = 14;
extern double RSI_OB               = 60.0;  // RSI buy threshold
extern double RSI_OS               = 40.0;  // RSI sell threshold

extern int    ATR_Period           = 14;
extern double ATR_Multiplier       = 1.5;   // ATR x for fallback SL

// Retest settings
extern bool   UseRetestEntry       = true;  // Wait for EMA retest before entering
extern int    MaxRetestBars        = 10;    // Cancel retest signal after N bars
extern double RetestATRTolerance   = 0.5;  // How close price must get to fast EMA (ATR units)

extern bool   UseLondonSession     = true;
extern bool   UseNewYorkSession    = true;

//--- State
datetime lastBarTime    = 0;
bool     waitBullRetest = false;
bool     waitBearRetest = false;
int      bullRetestBars = 0;
int      bearRetestBars = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   Print("HighWinRate EA v1.10 (MT4) initialized | Retest=",
         (UseRetestEntry ? "ON" : "OFF"), " MaxBars=", MaxRetestBars);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(Symbol(), PERIOD_H1, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;

   if(!IsValidSession()) return;
   if(CountOpenOrders() >= MaxOpenTrades) return;

   // --- Indicator values on last closed bar (index 1) and one before (index 2)
   double fastNow  = iMA(Symbol(), PERIOD_H1, EMA_Fast,  0, MODE_EMA, PRICE_CLOSE, 1);
   double fastPrev = iMA(Symbol(), PERIOD_H1, EMA_Fast,  0, MODE_EMA, PRICE_CLOSE, 2);
   double slowNow  = iMA(Symbol(), PERIOD_H1, EMA_Slow,  0, MODE_EMA, PRICE_CLOSE, 1);
   double slowPrev = iMA(Symbol(), PERIOD_H1, EMA_Slow,  0, MODE_EMA, PRICE_CLOSE, 2);
   double trendNow = iMA(Symbol(), PERIOD_H1, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE, 1);
   double rsiNow   = iRSI(Symbol(), PERIOD_H1, RSI_Period, PRICE_CLOSE, 1);
   double atrNow   = iATR(Symbol(), PERIOD_H1, ATR_Period, 1);

   double closeLast = iClose(Symbol(), PERIOD_H1, 1);
   double lowLast   = iLow (Symbol(), PERIOD_H1, 1);
   double highLast  = iHigh(Symbol(), PERIOD_H1, 1);

   double ask = Ask;
   double bid = Bid;

   bool bullCross = (fastPrev < slowPrev) && (fastNow > slowNow);
   bool bearCross = (fastPrev > slowPrev) && (fastNow < slowNow);

   // --- Crossover detected: set retest pending or enter immediately
   if(bullCross)
   {
      bearRetestBars = 0;
      waitBearRetest = false;

      if(UseRetestEntry)
      {
         waitBullRetest = true;
         bullRetestBars = 0;
         Print("BULL cross detected - waiting for EMA retest (max ", MaxRetestBars, " bars)");
      }
      else if(ask > trendNow && rsiNow > RSI_OB)
      {
         OpenBuy(ask, atrNow, rsiNow);
      }
   }

   if(bearCross)
   {
      bullRetestBars = 0;
      waitBullRetest = false;

      if(UseRetestEntry)
      {
         waitBearRetest = true;
         bearRetestBars = 0;
         Print("BEAR cross detected - waiting for EMA retest (max ", MaxRetestBars, " bars)");
      }
      else if(bid < trendNow && rsiNow < RSI_OS)
      {
         OpenSell(bid, atrNow, rsiNow);
      }
   }

   // --- Retest logic: check each bar after the cross
   if(UseRetestEntry)
   {
      // BULL RETEST
      if(waitBullRetest && !bullCross)
      {
         bullRetestBars++;

         double tolerance = atrNow * RetestATRTolerance;

         // Retest condition: bar's low came down to touch the fast EMA zone
         bool retested = (lowLast <= fastNow + tolerance);
         // Bounce condition: closed above fast EMA (bullish reaction)
         bool bounced  = (closeLast > fastNow);

         if(retested && bounced)
         {
            Print("BULL retest confirmed on bar ", bullRetestBars,
                  " | Low=", DoubleToStr(lowLast,5),
                  " FastEMA=", DoubleToStr(fastNow,5));

            if(ask > trendNow && rsiNow > RSI_OB)
            {
               // SL = below retest bar low (more precise than ATR alone)
               double slFromRetest = lowLast - atrNow * 0.2;
               double slFromATR    = ask - atrNow * ATR_Multiplier;
               // Use whichever gives a wider (safer) SL
               double sl = MathMin(slFromRetest, slFromATR);
               OpenBuyWithSL(ask, sl, atrNow, rsiNow);
            }
            else
               Print("BULL retest: trend/RSI filter blocked entry");

            waitBullRetest = false;
            bullRetestBars = 0;
         }
         else if(bullRetestBars >= MaxRetestBars)
         {
            Print("BULL retest expired after ", MaxRetestBars, " bars - signal cancelled");
            waitBullRetest = false;
            bullRetestBars = 0;
         }
      }

      // BEAR RETEST
      if(waitBearRetest && !bearCross)
      {
         bearRetestBars++;

         double tolerance = atrNow * RetestATRTolerance;

         // Retest condition: bar's high came back up to touch the fast EMA zone
         bool retested = (highLast >= fastNow - tolerance);
         // Rejection condition: closed below fast EMA (bearish reaction)
         bool rejected = (closeLast < fastNow);

         if(retested && rejected)
         {
            Print("BEAR retest confirmed on bar ", bearRetestBars,
                  " | High=", DoubleToStr(highLast,5),
                  " FastEMA=", DoubleToStr(fastNow,5));

            if(bid < trendNow && rsiNow < RSI_OS)
            {
               // SL = above retest bar high
               double slFromRetest = highLast + atrNow * 0.2;
               double slFromATR    = bid + atrNow * ATR_Multiplier;
               double sl = MathMax(slFromRetest, slFromATR);
               OpenSellWithSL(bid, sl, atrNow, rsiNow);
            }
            else
               Print("BEAR retest: trend/RSI filter blocked entry");

            waitBearRetest = false;
            bearRetestBars = 0;
         }
         else if(bearRetestBars >= MaxRetestBars)
         {
            Print("BEAR retest expired after ", MaxRetestBars, " bars - signal cancelled");
            waitBearRetest = false;
            bearRetestBars = 0;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Open BUY (immediate cross entry, ATR-based SL)                   |
//+------------------------------------------------------------------+
void OpenBuy(double ask, double atrNow, double rsiNow)
{
   double sl   = ask - (atrNow * ATR_Multiplier);
   OpenBuyWithSL(ask, sl, atrNow, rsiNow);
}

//+------------------------------------------------------------------+
//| Open BUY with explicit SL                                        |
//+------------------------------------------------------------------+
void OpenBuyWithSL(double ask, double sl, double atrNow, double rsiNow)
{
   double slDist = ask - sl;
   double tp     = NormalizeDouble(ask + slDist * RR_Ratio, Digits);
   sl            = NormalizeDouble(sl, Digits);
   double lots   = CalculateLotSize(slDist);

   if(lots <= 0) return;

   int ticket = OrderSend(Symbol(), OP_BUY, lots, ask, Slippage, sl, tp,
                          "HWR_Buy", MagicNumber, 0, clrBlue);
   if(ticket < 0)
      Print("BUY OrderSend failed, error: ", GetLastError());
   else
      Print("BUY opened | RSI=", DoubleToStr(rsiNow,2),
            " SL=", DoubleToStr(sl,5),
            " TP=", DoubleToStr(tp,5),
            " Lots=", DoubleToStr(lots,2));
}

//+------------------------------------------------------------------+
//| Open SELL (immediate cross entry, ATR-based SL)                  |
//+------------------------------------------------------------------+
void OpenSell(double bid, double atrNow, double rsiNow)
{
   double sl   = bid + (atrNow * ATR_Multiplier);
   OpenSellWithSL(bid, sl, atrNow, rsiNow);
}

//+------------------------------------------------------------------+
//| Open SELL with explicit SL                                       |
//+------------------------------------------------------------------+
void OpenSellWithSL(double bid, double sl, double atrNow, double rsiNow)
{
   double slDist = sl - bid;
   double tp     = NormalizeDouble(bid - slDist * RR_Ratio, Digits);
   sl            = NormalizeDouble(sl, Digits);
   double lots   = CalculateLotSize(slDist);

   if(lots <= 0) return;

   int ticket = OrderSend(Symbol(), OP_SELL, lots, bid, Slippage, sl, tp,
                          "HWR_Sell", MagicNumber, 0, clrRed);
   if(ticket < 0)
      Print("SELL OrderSend failed, error: ", GetLastError());
   else
      Print("SELL opened | RSI=", DoubleToStr(rsiNow,2),
            " SL=", DoubleToStr(sl,5),
            " TP=", DoubleToStr(tp,5),
            " Lots=", DoubleToStr(lots,2));
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk %                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints)
{
   if(slPoints <= 0) { Print("LotCalc: slPoints<=0, skip"); return 0; }

   double accountBalance = AccountBalance();
   double riskAmount     = accountBalance * RiskPercent / 100.0;
   double tickValue      = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize       = MarketInfo(Symbol(), MODE_TICKSIZE);
   double lotStep        = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot         = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot         = MarketInfo(Symbol(), MODE_MAXLOT);

   Print("LotCalc | Balance=", DoubleToStr(accountBalance,2),
         " Risk%=", DoubleToStr(RiskPercent,1),
         " RiskAmt=", DoubleToStr(riskAmount,2),
         " SLdist=", DoubleToStr(slPoints,5),
         " TickVal=", DoubleToStr(tickValue,5),
         " TickSz=",  DoubleToStr(tickSize,5));

   if(accountBalance <= 0) { Print("LotCalc: AccountBalance=0, skip trade"); return 0; }
   if(tickValue == 0 || tickSize == 0) { Print("LotCalc: tickValue/tickSize=0, skip"); return 0; }

   double valuePerLot = (slPoints / tickSize) * tickValue;
   if(valuePerLot <= 0) { Print("LotCalc: valuePerLot<=0, skip"); return 0; }

   double rawLots = riskAmount / valuePerLot;
   double lots    = MathFloor(rawLots / lotStep) * lotStep;

   Print("LotCalc | ValPerLot=", DoubleToStr(valuePerLot,2),
         " RawLots=", DoubleToStr(rawLots,4),
         " Floored=", DoubleToStr(lots,2),
         " MinLot=",  DoubleToStr(minLot,2));

   if(lots < minLot) { Print("LotCalc: lots<minLot (", DoubleToStr(lots,4), "), skip trade"); return 0; }

   lots = MathMin(maxLot, lots);
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Count open orders for this EA on current symbol                  |
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
//| Session filter - GMT time check                                  |
//+------------------------------------------------------------------+
bool IsValidSession()
{
   int hour     = TimeHour(TimeGMT());
   bool london  = UseLondonSession  && (hour >= 8  && hour < 17);
   bool newyork = UseNewYorkSession && (hour >= 13 && hour < 22);
   return (london || newyork);
}
//+------------------------------------------------------------------+
