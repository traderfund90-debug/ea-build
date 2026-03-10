//+------------------------------------------------------------------+
//|                                            OrderBlock_EA.mq4     |
//|                                         traderfund90-debug       |
//|    Order Block + Impulse Candle Count  –  XAUUSD Scalper        |
//|                                                                  |
//|  HOW IT WORKS:                                                   |
//|  BULLISH OB = last RED candle before N consecutive GREEN candles |
//|               that broke above the red candle's high             |
//|  → BUY when price retraces back into that red candle's zone     |
//|                                                                  |
//|  BEARISH OB = last GREEN candle before N consecutive RED candles |
//|               that broke below the green candle's low            |
//|  → SELL when price retraces back into that green candle's zone  |
//+------------------------------------------------------------------+
#property copyright "traderfund90-debug"
#property version   "1.00"
#property strict

//--- Timeframes
extern ENUM_TIMEFRAMES EntryTF           = PERIOD_M15;  // Chart TF for OB detection
extern ENUM_TIMEFRAMES TrendTF           = PERIOD_H1;   // Higher TF trend filter

//--- Risk Management
extern double RiskPercent                = 1.0;         // % of balance per trade
extern double RR_Ratio                   = 2.0;         // TP = SL distance x this
extern int    MagicNumber                = 404800;
extern int    MaxOpenTrades              = 1;
extern int    MaxTradesPerDay            = 4;
extern int    Slippage                   = 5;

//--- Spread Filter
extern double MaxSpreadPoints            = 40.0;        // Skip if spread > this (points)

//--- Order Block Settings
extern int    OB_Lookback                = 60;          // How many bars back to scan for OBs
extern int    MinImpulseCandles          = 3;           // Min consecutive same-color candles after OB
extern bool   UseBodyOnly                = false;       // true = OB zone uses body; false = full wick

//--- Trend Filter
extern int    EMA_Trend                  = 200;         // Trend EMA on TrendTF

//--- ATR Stop Loss
extern int    ATR_Period                 = 14;
extern double ATR_SL_Buffer              = 0.3;         // Extra ATR buffer below/above OB zone

//--- Session Filter (GMT)
extern bool   UseLondonSession           = true;        // 08:00 – 17:00 GMT
extern bool   UseNewYorkSession          = true;        // 13:00 – 22:00 GMT

//--- State
datetime lastBarTime  = 0;
int      tradesToday  = 0;
datetime lastTradeDay = 0;

//--- Detected OB zones
double bullOB_High = 0, bullOB_Low = 0;
double bearOB_High = 0, bearOB_Low = 0;
bool   bullOBValid = false;
bool   bearOBValid = false;

//+------------------------------------------------------------------+
int OnInit()
{
   Print("OrderBlock EA v1.00 | TF=", EnumToString(EntryTF),
         " | TrendTF=", EnumToString(TrendTF),
         " | MinImpulse=", MinImpulseCandles,
         " | Lookback=", OB_Lookback);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
void OnTick()
{
   //--- New bar guard (run logic once per closed bar)
   datetime currentBar = iTime(Symbol(), EntryTF, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;

   //--- Daily counter reset
   ResetDailyCounter();

   //--- Pre-flight checks
   if(!IsValidSession())              return;
   if(tradesToday >= MaxTradesPerDay) return;
   if(CountOpenOrders() >= MaxOpenTrades) return;

   double spread = (Ask - Bid) / Point;
   if(spread > MaxSpreadPoints)
   {
      Print("Spread blocked: ", DoubleToStr(spread,0), " pts");
      return;
   }

   //--- Trend filter
   double trendEMA   = iMA(Symbol(), TrendTF, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE, 1);
   double trendClose = iClose(Symbol(), TrendTF, 1);
   bool   bullTrend  = (trendClose > trendEMA);
   bool   bearTrend  = (trendClose < trendEMA);

   //--- ATR for SL buffer
   double atr = iATR(Symbol(), EntryTF, ATR_Period, 1);

   //--- Scan for fresh order blocks every bar
   ScanOrderBlocks();

   double ask = Ask;
   double bid = Bid;

   //=================================================================
   //  BUY ENTRY
   //  Condition: bullish trend + price returned into bullish OB zone
   //=================================================================
   if(bullTrend && bullOBValid)
   {
      if(ask >= bullOB_Low && ask <= bullOB_High)
      {
         // SL = below OB low with ATR buffer
         double sl   = NormalizeDouble(bullOB_Low - atr * ATR_SL_Buffer, Digits);
         double dist = ask - sl;
         if(dist > 0)
         {
            double tp   = NormalizeDouble(ask + dist * RR_Ratio, Digits);
            double lots = CalculateLotSize(dist);

            if(lots > 0)
            {
               int ticket = OrderSend(Symbol(), OP_BUY, lots, ask, Slippage,
                                      sl, tp, "OB_Buy", MagicNumber, 0, clrDodgerBlue);
               if(ticket < 0)
                  Print("OB BUY failed – error: ", GetLastError());
               else
               {
                  tradesToday++;
                  bullOBValid = false; // OB consumed, don't re-enter
                  Print("OB BUY | Zone=", DoubleToStr(bullOB_Low,2), "-", DoubleToStr(bullOB_High,2),
                        " | SL=", DoubleToStr(sl,2),
                        " | TP=", DoubleToStr(tp,2),
                        " | Lots=", DoubleToStr(lots,2));
               }
            }
         }
      }
   }

   //=================================================================
   //  SELL ENTRY
   //  Condition: bearish trend + price returned into bearish OB zone
   //=================================================================
   if(bearTrend && bearOBValid)
   {
      if(bid >= bearOB_Low && bid <= bearOB_High)
      {
         // SL = above OB high with ATR buffer
         double sl   = NormalizeDouble(bearOB_High + atr * ATR_SL_Buffer, Digits);
         double dist = sl - bid;
         if(dist > 0)
         {
            double tp   = NormalizeDouble(bid - dist * RR_Ratio, Digits);
            double lots = CalculateLotSize(dist);

            if(lots > 0)
            {
               int ticket = OrderSend(Symbol(), OP_SELL, lots, bid, Slippage,
                                      sl, tp, "OB_Sell", MagicNumber, 0, clrOrangeRed);
               if(ticket < 0)
                  Print("OB SELL failed – error: ", GetLastError());
               else
               {
                  tradesToday++;
                  bearOBValid = false; // OB consumed
                  Print("OB SELL | Zone=", DoubleToStr(bearOB_Low,2), "-", DoubleToStr(bearOB_High,2),
                        " | SL=", DoubleToStr(sl,2),
                        " | TP=", DoubleToStr(tp,2),
                        " | Lots=", DoubleToStr(lots,2));
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//|  SCAN ORDER BLOCKS                                               |
//|                                                                  |
//|  Bar layout (MQL4 index convention):                            |
//|    Higher index = older bar.  Bar 1 = last closed.              |
//|                                                                  |
//|  OB candidate is at bar [i].                                    |
//|  Impulse bars come AFTER the OB = lower indices [i-1 .. i-N].  |
//|  We scan from i = (1+N) upward → finds the MOST RECENT OB.     |
//+------------------------------------------------------------------+
void ScanOrderBlocks()
{
   bullOBValid = false;
   bearOBValid = false;

   int N = MinImpulseCandles;

   for(int i = 1 + N; i <= OB_Lookback; i++)
   {
      double obOpen  = iOpen (Symbol(), EntryTF, i);
      double obHigh  = iHigh (Symbol(), EntryTF, i);
      double obLow   = iLow  (Symbol(), EntryTF, i);
      double obClose = iClose(Symbol(), EntryTF, i);

      bool isRed   = (obClose < obOpen);  // Red candle  → potential bullish OB
      bool isGreen = (obClose > obOpen);  // Green candle → potential bearish OB

      //--------------------------------------------------------------
      //  BULLISH ORDER BLOCK
      //  Red candle at [i] + N green candles [i-1..i-N] + impulse
      //  broke above the red candle's high
      //--------------------------------------------------------------
      if(isRed && !bullOBValid)
      {
         int  greenCount = 0;
         bool brokeHigh  = false;

         for(int j = i - 1; j >= i - N; j--)
         {
            double cOpen  = iOpen (Symbol(), EntryTF, j);
            double cClose = iClose(Symbol(), EntryTF, j);
            double cHigh  = iHigh (Symbol(), EntryTF, j);

            if(cClose > cOpen) greenCount++;      // green candle
            if(cHigh  > obHigh) brokeHigh = true; // impulse cleared OB high
         }

         if(greenCount >= N && brokeHigh)
         {
            bullOB_High = UseBodyOnly ? MathMax(obOpen, obClose) : obHigh;
            bullOB_Low  = UseBodyOnly ? MathMin(obOpen, obClose) : obLow;
            bullOBValid = true;
            Print("Bullish OB found at bar ", i,
                  " | Zone=", DoubleToStr(bullOB_Low,2), "-", DoubleToStr(bullOB_High,2),
                  " | GreenCandles=", greenCount);
         }
      }

      //--------------------------------------------------------------
      //  BEARISH ORDER BLOCK
      //  Green candle at [i] + N red candles [i-1..i-N] + impulse
      //  broke below the green candle's low
      //--------------------------------------------------------------
      if(isGreen && !bearOBValid)
      {
         int  redCount = 0;
         bool brokeLow = false;

         for(int j = i - 1; j >= i - N; j--)
         {
            double cOpen  = iOpen (Symbol(), EntryTF, j);
            double cClose = iClose(Symbol(), EntryTF, j);
            double cLow   = iLow  (Symbol(), EntryTF, j);

            if(cClose < cOpen) redCount++;        // red candle
            if(cLow   < obLow) brokeLow = true;   // impulse cleared OB low
         }

         if(redCount >= N && brokeLow)
         {
            bearOB_High = UseBodyOnly ? MathMax(obOpen, obClose) : obHigh;
            bearOB_Low  = UseBodyOnly ? MathMin(obOpen, obClose) : obLow;
            bearOBValid = true;
            Print("Bearish OB found at bar ", i,
                  " | Zone=", DoubleToStr(bearOB_Low,2), "-", DoubleToStr(bearOB_High,2),
                  " | RedCandles=", redCount);
         }
      }

      if(bullOBValid && bearOBValid) break; // Both found – stop scanning
   }
}

//+------------------------------------------------------------------+
//| Lot size from risk %                                             |
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

   return NormalizeDouble(MathMin(lots, maxLot), 2);
}

//+------------------------------------------------------------------+
//| Count open orders for this EA                                    |
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
//| Reset daily trade counter on new day                             |
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
//| Session filter (GMT)                                             |
//+------------------------------------------------------------------+
bool IsValidSession()
{
   int  hour    = TimeHour(TimeGMT());
   bool london  = UseLondonSession  && (hour >= 8  && hour < 17);
   bool newyork = UseNewYorkSession && (hour >= 13 && hour < 22);
   return (london || newyork);
}
//+------------------------------------------------------------------+
