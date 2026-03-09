//+------------------------------------------------------------------+
//|                                             HighWinRate_EA.mq4   |
//|                                         traderfund90-debug       |
//|                    High Win Rate EA - Multi-Filter Confirmation   |
//+------------------------------------------------------------------+
#property copyright "traderfund90-debug"
#property version   "1.00"
#property strict

//--- Input Parameters
extern double RiskPercent       = 1.0;    // Risk % per trade
extern double RR_Ratio          = 2.0;    // Risk:Reward Ratio (TP = RR * SL)
extern int    MagicNumber       = 202600; // Magic Number
extern int    MaxOpenTrades     = 1;      // Max open trades at once
extern int    Slippage          = 3;      // Slippage in pips

extern int    EMA_Fast          = 21;     // Fast EMA period
extern int    EMA_Slow          = 50;     // Slow EMA period
extern int    EMA_Trend         = 200;    // Trend EMA period

extern int    RSI_Period        = 14;     // RSI period
extern double RSI_OB            = 60.0;  // RSI buy threshold (above)
extern double RSI_OS            = 40.0;  // RSI sell threshold (below)

extern int    ATR_Period        = 14;     // ATR period
extern double ATR_Multiplier    = 1.5;    // ATR multiplier for SL

extern bool   UseLondonSession  = true;   // Trade London session (08:00-17:00 GMT)
extern bool   UseNewYorkSession = true;   // Trade New York session (13:00-22:00 GMT)

//--- Global variables
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("HighWinRate EA (MT4) initialized on ", Symbol());
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only process on new H1 bar
   datetime currentBar = iTime(Symbol(), PERIOD_H1, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;

   // Session filter
   if(!IsValidSession()) return;

   // Count open positions
   if(CountOpenOrders() >= MaxOpenTrades) return;

   // Indicator values (index 1 = last closed bar, index 2 = bar before that)
   double fastNow  = iMA(Symbol(), PERIOD_H1, EMA_Fast,  0, MODE_EMA, PRICE_CLOSE, 1);
   double fastPrev = iMA(Symbol(), PERIOD_H1, EMA_Fast,  0, MODE_EMA, PRICE_CLOSE, 2);
   double slowNow  = iMA(Symbol(), PERIOD_H1, EMA_Slow,  0, MODE_EMA, PRICE_CLOSE, 1);
   double slowPrev = iMA(Symbol(), PERIOD_H1, EMA_Slow,  0, MODE_EMA, PRICE_CLOSE, 2);
   double trendNow = iMA(Symbol(), PERIOD_H1, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE, 1);
   double rsiNow   = iRSI(Symbol(), PERIOD_H1, RSI_Period, PRICE_CLOSE, 1);
   double atrNow   = iATR(Symbol(), PERIOD_H1, ATR_Period, 1);

   // EMA crossover detection
   bool bullCross = (fastPrev < slowPrev) && (fastNow > slowNow);
   bool bearCross = (fastPrev > slowPrev) && (fastNow < slowNow);

   double ask = Ask;
   double bid = Bid;

   bool aboveTrend = ask > trendNow;
   bool belowTrend = bid < trendNow;

   // BUY Signal: Bullish EMA cross + price above 200 EMA + RSI above threshold
   if(bullCross && aboveTrend && rsiNow > RSI_OB)
   {
      double sl   = ask - (atrNow * ATR_Multiplier);
      double tp   = ask + (atrNow * ATR_Multiplier * RR_Ratio);
      double lots = CalculateLotSize(ask - sl);

      sl = NormalizeDouble(sl, Digits);
      tp = NormalizeDouble(tp, Digits);

      if(lots > 0)
      {
         int ticket = OrderSend(Symbol(), OP_BUY, lots, ask, Slippage, sl, tp,
                                "HWR_Buy", MagicNumber, 0, clrBlue);
         if(ticket < 0)
            Print("BUY OrderSend failed, error: ", GetLastError());
         else
            Print("BUY opened: RSI=", DoubleToStr(rsiNow, 2),
                  " ATR=", DoubleToStr(atrNow, 5),
                  " Lots=", DoubleToStr(lots, 2));
      }
   }

   // SELL Signal: Bearish EMA cross + price below 200 EMA + RSI below threshold
   if(bearCross && belowTrend && rsiNow < RSI_OS)
   {
      double sl   = bid + (atrNow * ATR_Multiplier);
      double tp   = bid - (atrNow * ATR_Multiplier * RR_Ratio);
      double lots = CalculateLotSize(sl - bid);

      sl = NormalizeDouble(sl, Digits);
      tp = NormalizeDouble(tp, Digits);

      if(lots > 0)
      {
         int ticket = OrderSend(Symbol(), OP_SELL, lots, bid, Slippage, sl, tp,
                                "HWR_Sell", MagicNumber, 0, clrRed);
         if(ticket < 0)
            Print("SELL OrderSend failed, error: ", GetLastError());
         else
            Print("SELL opened: RSI=", DoubleToStr(rsiNow, 2),
                  " ATR=", DoubleToStr(atrNow, 5),
                  " Lots=", DoubleToStr(lots, 2));
      }
   }
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

   // Do NOT force minLot — if risk doesn't afford minimum lot, skip the trade
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
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
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
   datetime gmtTime = TimeGMT();
   int hour = TimeHour(gmtTime);

   bool london  = UseLondonSession  && (hour >= 8  && hour < 17);
   bool newyork = UseNewYorkSession && (hour >= 13 && hour < 22);

   return (london || newyork);
}
//+------------------------------------------------------------------+
