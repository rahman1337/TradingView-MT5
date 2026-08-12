//+------------------------------------------------------------------+
//| MT5_FVG_CE_AutoTrader.mq5                                       |
//|                                                                  |
//| Strategy                                                        |
//| 1. Detect the latest CONFIRMED M15 bullish FVG and bearish FVG. |
//| 2. Draw both M15 FVGs as entry zones and mark their CE.         |
//| 3. M5/tick confirmation: enter immediately when price crosses   |
//|    the CE of the latest valid FVG.                              |
//| 4. Bullish FVG -> BUY. Bearish FVG -> SELL.                    |
//| 5. SL is behind the FVG.                                        |
//| 6. At +30 pips, move SL to entry +5 pips / entry -5 pips.       |
//| 7. TP = 70 pips.                                                |
//|                                                                  |
//| Notes                                                            |
//| - A confirmed FVG is a 3-candle imbalance whose third candle     |
//|   has CLOSED.                                                    |
//| - Bullish FVG: Low(C3) > High(C1).                               |
//| - Bearish FVG: High(C3) < Low(C1).                              |
//| - CE = midpoint of the FVG.                                     |
//| - Only ONE EA position is allowed on this symbol at a time.     |
//| - The same FVG is never traded twice.                            |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "M15 FVG + M5 CE touch autotrader"

#include <Trade/Trade.mqh>

CTrade trade;

//====================================================================
// INPUTS
//====================================================================
input group "=== TRADE SETTINGS ==="
input double InpLots                 = 0.01;
input ulong  InpMagicNumber          = 26081201;
input int    InpDeviationPoints      = 30;
input int    InpLookbackM15Bars      = 300;
input double InpMinFVGSizePips       = 0.0;
input double InpSLBehindPips         = 1.0;
input double InpBreakEvenTriggerPips = 30.0;
input double InpBreakEvenPlusPips    = 5.0;
input double InpTakeProfitPips       = 70.0;

input group "=== ENTRY SETTINGS ==="
input bool   InpOnePositionPerSymbol = true;

input group "=== CHART DRAWING ==="
input bool   InpDrawFVG              = true;
input bool   InpDrawCE               = true;
input bool   InpDrawLabels           = true;
input int    InpFVGForwardBars       = 80;
input int    InpLineWidth            = 2;

input group "=== DASHBOARD ==="
input bool   InpShowDashboard        = true;
input int    InpDashboardX           = 18;
input int    InpDashboardY           = 28;
input int    InpDashboardTextSize    = 10;
input int    InpDashboardLineHeight  = 17;

//====================================================================
// CONSTANTS / OBJECT NAMES
//====================================================================
#define PREFIX            "FVGCE_EA_"
#define OBJ_BULL_FVG      PREFIX+"BULL_FVG"
#define OBJ_BEAR_FVG      PREFIX+"BEAR_FVG"
#define OBJ_BULL_CE       PREFIX+"BULL_CE"
#define OBJ_BEAR_CE       PREFIX+"BEAR_CE"
#define OBJ_BULL_TEXT     PREFIX+"BULL_TEXT"
#define OBJ_BEAR_TEXT     PREFIX+"BEAR_TEXT"
#define OBJ_ENTRY_LINE    PREFIX+"ENTRY_LINE"
#define OBJ_SL_LINE       PREFIX+"SL_LINE"
#define OBJ_TP_LINE       PREFIX+"TP_LINE"

#define DASH_TITLE        PREFIX+"DASH_TITLE"
#define DASH_SYMBOL       PREFIX+"DASH_SYMBOL"
#define DASH_BULL         PREFIX+"DASH_BULL"
#define DASH_BEAR         PREFIX+"DASH_BEAR"
#define DASH_CE           PREFIX+"DASH_CE"
#define DASH_POSITION     PREFIX+"DASH_POSITION"
#define DASH_BALANCE      PREFIX+"DASH_BALANCE"
#define DASH_EQUITY       PREFIX+"DASH_EQUITY"
#define DASH_STATUS       PREFIX+"DASH_STATUS"

//====================================================================
// STRUCTURES
//====================================================================
struct FVGZone
{
   bool     valid;
   bool     bullish;
   datetime candleTime;     // time of C3, the confirmation candle
   datetime startTime;      // chart rectangle start
   double   low;
   double   high;
   double   ce;
   double   sizePips;
};

//====================================================================
// GLOBALS
//====================================================================
FVGZone gBull;
FVGZone gBear;

double gPrevBid = 0.0;
double gPrevAsk = 0.0;

datetime gLastTradedBullTime = 0;
datetime gLastTradedBearTime = 0;

string GV_BULL = "";
string GV_BEAR = "";

//====================================================================
// PIP / PRICE HELPERS
//====================================================================
double PipSize()
{
   // For 5/3-digit symbols: 1 pip = 10 points.
   // Example XAUUSD with 3 digits: _Point=0.01 -> pip=0.10.
   if(_Digits == 3 || _Digits == 5)
      return(10.0 * _Point);

   return(_Point);
}

double PipsToPrice(const double pips)
{
   return(pips * PipSize());
}

double NormalizePrice(const double price)
{
   return(NormalizeDouble(price, _Digits));
}

string PriceToString(const double price)
{
   if(price <= 0.0)
      return("-");

   return(DoubleToString(price, _Digits));
}

//====================================================================
// GLOBAL VARIABLE PERSISTENCE
//====================================================================
void LoadTradedFVGState()
{
   GV_BULL = PREFIX + "LAST_BULL_" + _Symbol + "_" + IntegerToString((int)InpMagicNumber);
   GV_BEAR = PREFIX + "LAST_BEAR_" + _Symbol + "_" + IntegerToString((int)InpMagicNumber);

   if(GlobalVariableCheck(GV_BULL))
      gLastTradedBullTime = (datetime)(long)GlobalVariableGet(GV_BULL);

   if(GlobalVariableCheck(GV_BEAR))
      gLastTradedBearTime = (datetime)(long)GlobalVariableGet(GV_BEAR);
}

void SaveTradedFVGState(const bool bullish, const datetime t)
{
   if(bullish)
   {
      gLastTradedBullTime = t;
      if(GV_BULL != "")
         GlobalVariableSet(GV_BULL, (double)t);
   }
   else
   {
      gLastTradedBearTime = t;
      if(GV_BEAR != "")
         GlobalVariableSet(GV_BEAR, (double)t);
   }
}

//====================================================================
// FVG DETECTION
//====================================================================
void ClearFVG(FVGZone &fvg)
{
   fvg.valid      = false;
   fvg.bullish    = false;
   fvg.candleTime = 0;
   fvg.startTime  = 0;
   fvg.low        = 0.0;
   fvg.high       = 0.0;
   fvg.ce         = 0.0;
   fvg.sizePips   = 0.0;
}

bool IsBullishFVG(const MqlRates &c1,
                  const MqlRates &c2,
                  const MqlRates &c3,
                  double &zoneLow,
                  double &zoneHigh)
{
   // C1 -> C2 -> C3, where C3 is already closed.
   // Bullish imbalance = Low(C3) > High(C1).
   if(c3.low <= c1.high)
      return(false);

   zoneLow  = c1.high;
   zoneHigh = c3.low;

   return(zoneHigh > zoneLow);
}

bool IsBearishFVG(const MqlRates &c1,
                  const MqlRates &c2,
                  const MqlRates &c3,
                  double &zoneLow,
                  double &zoneHigh)
{
   // Bearish imbalance = High(C3) < Low(C1).
   if(c3.high >= c1.low)
      return(false);

   zoneLow  = c3.high;
   zoneHigh = c1.low;

   return(zoneHigh > zoneLow);
}

bool DetectLatestFVGs(FVGZone &latestBull, FVGZone &latestBear)
{
   ClearFVG(latestBull);
   ClearFVG(latestBear);

   int needBars = MathMax(InpLookbackM15Bars + 5, 20);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int copied = CopyRates(_Symbol, PERIOD_M15, 0, needBars, rates);
   if(copied < 4)
      return(false);

   bool foundBull = false;
   bool foundBear = false;

   // i=1 is the latest CLOSED M15 candle (C3).
   // c1 = i+2, c2 = i+1, c3 = i.
   for(int i = 1; i + 2 < copied; i++)
   {
      MqlRates c3 = rates[i];
      MqlRates c2 = rates[i+1];
      MqlRates c1 = rates[i+2];

      double zl = 0.0;
      double zh = 0.0;

      if(!foundBull && IsBullishFVG(c1,c2,c3,zl,zh))
      {
         double sizePips = (zh-zl) / PipSize();

         if(sizePips >= InpMinFVGSizePips)
         {
            latestBull.valid      = true;
            latestBull.bullish    = true;
            latestBull.candleTime = c3.time;
            latestBull.startTime  = c3.time;
            latestBull.low        = NormalizePrice(zl);
            latestBull.high       = NormalizePrice(zh);
            latestBull.ce         = NormalizePrice((zl+zh)/2.0);
            latestBull.sizePips   = sizePips;

            foundBull = true;
         }
      }

      if(!foundBear && IsBearishFVG(c1,c2,c3,zl,zh))
      {
         double sizePips = (zh-zl) / PipSize();

         if(sizePips >= InpMinFVGSizePips)
         {
            latestBear.valid      = true;
            latestBear.bullish    = false;
            latestBear.candleTime = c3.time;
            latestBear.startTime  = c3.time;
            latestBear.low        = NormalizePrice(zl);
            latestBear.high       = NormalizePrice(zh);
            latestBear.ce         = NormalizePrice((zl+zh)/2.0);
            latestBear.sizePips   = sizePips;

            foundBear = true;
         }
      }

      if(foundBull && foundBear)
         break;
   }

   return(foundBull || foundBear);
}

//====================================================================
// POSITION HELPERS
//====================================================================
bool HasOurPosition()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);

      if(sym == _Symbol && (ulong)magic == InpMagicNumber)
         return(true);
   }

   return(false);
}

bool HasAnySymbolPosition()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         return(true);
   }

   return(false);
}

bool CanOpenTrade()
{
   if(InpOnePositionPerSymbol)
   {
      if(HasAnySymbolPosition())
         return(false);
   }
   else
   {
      if(HasOurPosition())
         return(false);
   }

   return(true);
}

bool IsTradeFVGAlreadyUsed(const bool bullish, const datetime fvgTime)
{
   if(bullish)
      return(gLastTradedBullTime == fvgTime);

   return(gLastTradedBearTime == fvgTime);
}

//====================================================================
// BROKER / STOP DISTANCE
//====================================================================
double MinStopDistancePrice()
{
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopsLevel < 0)
      stopsLevel = 0;

   return((double)stopsLevel * _Point);
}

double MakeValidSL(const ENUM_ORDER_TYPE type, double requestedSL, const MqlTick &tick)
{
   double minDist = MinStopDistancePrice();

   if(type == ORDER_TYPE_BUY)
   {
      double maxSL = tick.bid - minDist;
      if(requestedSL > maxSL)
         requestedSL = maxSL;
   }
   else if(type == ORDER_TYPE_SELL)
   {
      double minSL = tick.ask + minDist;
      if(requestedSL < minSL)
         requestedSL = minSL;
   }

   return(NormalizePrice(requestedSL));
}

double MakeValidTP(const ENUM_ORDER_TYPE type, double requestedTP, const MqlTick &tick)
{
   double minDist = MinStopDistancePrice();

   if(type == ORDER_TYPE_BUY)
   {
      double minTP = tick.ask + minDist;
      if(requestedTP < minTP)
         requestedTP = minTP;
   }
   else if(type == ORDER_TYPE_SELL)
   {
      double maxTP = tick.bid - minDist;
      if(requestedTP > maxTP)
         requestedTP = maxTP;
   }

   return(NormalizePrice(requestedTP));
}

//====================================================================
// TRADE EXECUTION
//====================================================================
bool OpenBuy(const FVGZone &fvg, const MqlTick &tick)
{
   if(!CanOpenTrade())
      return(false);

   if(IsTradeFVGAlreadyUsed(true, fvg.candleTime))
      return(false);

   double sl = fvg.low - PipsToPrice(InpSLBehindPips);
   double tp = tick.ask + PipsToPrice(InpTakeProfitPips);

   sl = MakeValidSL(ORDER_TYPE_BUY, sl, tick);
   tp = MakeValidTP(ORDER_TYPE_BUY, tp, tick);

   if(sl <= 0.0 || sl >= tick.ask)
      return(false);

   if(tp <= tick.ask)
      return(false);

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   string comment = "M15 Bullish FVG CE BUY";

   bool result = trade.Buy(InpLots, _Symbol, 0.0, sl, tp, comment);

   if(result)
   {
      SaveTradedFVGState(true, fvg.candleTime);
      Print("BUY opened | FVG=", TimeToString(fvg.candleTime),
            " | CE=", PriceToString(fvg.ce),
            " | SL=", PriceToString(sl),
            " | TP=", PriceToString(tp));
   }
   else
   {
      Print("BUY failed. Retcode=", trade.ResultRetcode(),
            " ", trade.ResultRetcodeDescription());
   }

   return(result);
}

bool OpenSell(const FVGZone &fvg, const MqlTick &tick)
{
   if(!CanOpenTrade())
      return(false);

   if(IsTradeFVGAlreadyUsed(false, fvg.candleTime))
      return(false);

   double sl = fvg.high + PipsToPrice(InpSLBehindPips);
   double tp = tick.bid - PipsToPrice(InpTakeProfitPips);

   sl = MakeValidSL(ORDER_TYPE_SELL, sl, tick);
   tp = MakeValidTP(ORDER_TYPE_SELL, tp, tick);

   if(sl <= tick.bid)
      return(false);

   if(tp <= 0.0 || tp >= tick.bid)
      return(false);

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   string comment = "M15 Bearish FVG CE SELL";

   bool result = trade.Sell(InpLots, _Symbol, 0.0, sl, tp, comment);

   if(result)
   {
      SaveTradedFVGState(false, fvg.candleTime);
      Print("SELL opened | FVG=", TimeToString(fvg.candleTime),
            " | CE=", PriceToString(fvg.ce),
            " | SL=", PriceToString(sl),
            " | TP=", PriceToString(tp));
   }
   else
   {
      Print("SELL failed. Retcode=", trade.ResultRetcode(),
            " ", trade.ResultRetcodeDescription());
   }

   return(result);
}

//====================================================================
// CE ENTRY CONFIRMATION
//====================================================================
bool BullishCEReached(const FVGZone &fvg, const MqlTick &tick)
{
   if(!fvg.valid)
      return(false);

   // M5 confirmation:
   // - Live tick crossing of CE is the fastest trigger.
   // - The current M5 candle low is also checked so a very fast CE
   //   touch is not missed between ticks.
   datetime m5Time = iTime(_Symbol,PERIOD_M5,0);
   double   m5Low  = iLow(_Symbol,PERIOD_M5,0);

   bool tickCross = (gPrevAsk > 0.0 &&
                     gPrevAsk > fvg.ce &&
                     tick.ask <= fvg.ce);

   bool m5Touch = (m5Time >= fvg.candleTime &&
                   m5Low > 0.0 &&
                   m5Low <= fvg.ce);

   return(tickCross || m5Touch);
}

bool BearishCEReached(const FVGZone &fvg, const MqlTick &tick)
{
   if(!fvg.valid)
      return(false);

   // M5 confirmation:
   // - Live tick crossing of CE is the fastest trigger.
   // - The current M5 candle high is also checked so a very fast CE
   //   touch is not missed between ticks.
   datetime m5Time = iTime(_Symbol,PERIOD_M5,0);
   double   m5High = iHigh(_Symbol,PERIOD_M5,0);

   bool tickCross = (gPrevBid > 0.0 &&
                     gPrevBid < fvg.ce &&
                     tick.bid >= fvg.ce);

   bool m5Touch = (m5Time >= fvg.candleTime &&
                   m5High > 0.0 &&
                   m5High >= fvg.ce);

   return(tickCross || m5Touch);
}

void CheckForEntries()
{
   if(!CanOpenTrade())
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   bool bullTouch = BullishCEReached(gBull,tick);
   bool bearTouch = BearishCEReached(gBear,tick);

   if(!bullTouch && !bearTouch)
      return;

   if(bullTouch && !bearTouch)
   {
      OpenBuy(gBull,tick);
      return;
   }

   if(bearTouch && !bullTouch)
   {
      OpenSell(gBear,tick);
      return;
   }

   // If both latest zones are touched at the same time, choose the
   // zone whose CE is closest to current price.
   double bullDistance = MathAbs(tick.ask-gBull.ce);
   double bearDistance = MathAbs(tick.bid-gBear.ce);

   if(bullDistance <= bearDistance)
      OpenBuy(gBull,tick);
   else
      OpenSell(gBear,tick);
}

//====================================================================
// TRADE MANAGEMENT
//====================================================================
bool ModifyPositionSLTP(const ulong ticket, const double newSL, const double currentTP)
{
   if(!PositionSelectByTicket(ticket))
      return(false);

   string symbol = PositionGetString(POSITION_SYMBOL);

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   bool ok = trade.PositionModify(symbol, NormalizePrice(newSL), NormalizePrice(currentTP));

   if(!ok)
   {
      Print("PositionModify failed. Ticket=",ticket,
            " Retcode=",trade.ResultRetcode(),
            " ",trade.ResultRetcodeDescription());
   }

   return(ok);
}

void ManageBreakEven()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   double trigger = PipsToPrice(InpBreakEvenTriggerPips);
   double plus    = PipsToPrice(InpBreakEvenPlusPips);

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic    = PositionGetInteger(POSITION_MAGIC);

      if(symbol != _Symbol || (ulong)magic != InpMagicNumber)
         continue;

      long type       = PositionGetInteger(POSITION_TYPE);
      double open     = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl       = PositionGetDouble(POSITION_SL);
      double tp       = PositionGetDouble(POSITION_TP);

      if(type == POSITION_TYPE_BUY)
      {
         double profitDistance = tick.bid - open;

         if(profitDistance >= trigger)
         {
            double beSL = open + plus;
            beSL = MakeValidSL(ORDER_TYPE_BUY, beSL, tick);

            // Never move SL backwards.
            if(sl == 0.0 || beSL > sl + (_Point*0.5))
               ModifyPositionSLTP(ticket,beSL,tp);
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double profitDistance = open - tick.ask;

         if(profitDistance >= trigger)
         {
            double beSL = open - plus;
            beSL = MakeValidSL(ORDER_TYPE_SELL, beSL, tick);

            // Never move SL backwards.
            if(sl == 0.0 || beSL < sl - (_Point*0.5))
               ModifyPositionSLTP(ticket,beSL,tp);
         }
      }
   }
}

//====================================================================
// CHART OBJECT HELPERS
//====================================================================
void DeleteObjectIfExists(const string name)
{
   if(ObjectFind(0,name) >= 0)
      ObjectDelete(0,name);
}

void DeleteAllEAObjects()
{
   DeleteObjectIfExists(OBJ_BULL_FVG);
   DeleteObjectIfExists(OBJ_BEAR_FVG);
   DeleteObjectIfExists(OBJ_BULL_CE);
   DeleteObjectIfExists(OBJ_BEAR_CE);
   DeleteObjectIfExists(OBJ_BULL_TEXT);
   DeleteObjectIfExists(OBJ_BEAR_TEXT);
   DeleteObjectIfExists(OBJ_ENTRY_LINE);
   DeleteObjectIfExists(OBJ_SL_LINE);
   DeleteObjectIfExists(OBJ_TP_LINE);

   DeleteObjectIfExists(DASH_TITLE);
   DeleteObjectIfExists(DASH_SYMBOL);
   DeleteObjectIfExists(DASH_BULL);
   DeleteObjectIfExists(DASH_BEAR);
   DeleteObjectIfExists(DASH_CE);
   DeleteObjectIfExists(DASH_POSITION);
   DeleteObjectIfExists(DASH_BALANCE);
   DeleteObjectIfExists(DASH_EQUITY);
   DeleteObjectIfExists(DASH_STATUS);
}

void DrawRectangleZone(const string name,
                       const datetime t1,
                       const datetime t2,
                       const double priceLow,
                       const double priceHigh,
                       const color clr)
{
   if(ObjectFind(0,name) < 0)
   {
      if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,priceHigh,t2,priceLow))
         return;
   }
   else
   {
      ObjectMove(0,name,0,t1,priceHigh);
      ObjectMove(0,name,1,t2,priceLow);
   }

   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,InpLineWidth);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void DrawHorizontalPriceLine(const string name,
                             const double price,
                             const color clr,
                             const ENUM_LINE_STYLE style=STYLE_DASH)
{
   if(ObjectFind(0,name) < 0)
   {
      if(!ObjectCreate(0,name,OBJ_HLINE,0,0,price))
         return;
   }

   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void DrawTextAtPrice(const string name,
                     const string text,
                     const datetime t,
                     const double price,
                     const color clr)
{
   if(ObjectFind(0,name) < 0)
   {
      if(!ObjectCreate(0,name,OBJ_TEXT,0,t,price))
         return;
   }
   else
   {
      ObjectMove(0,name,0,t,price);
   }

   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

//====================================================================
// CHART DRAWING
//====================================================================
datetime DrawingEndTime()
{
   int seconds = PeriodSeconds(PERIOD_M15);
   if(seconds <= 0)
      seconds = 900;

   return(TimeCurrent() + (datetime)(seconds * InpFVGForwardBars));
}

void DrawFVGs()
{
   if(!InpDrawFVG)
   {
      DeleteObjectIfExists(OBJ_BULL_FVG);
      DeleteObjectIfExists(OBJ_BEAR_FVG);
      DeleteObjectIfExists(OBJ_BULL_TEXT);
      DeleteObjectIfExists(OBJ_BEAR_TEXT);
   }

   if(!InpDrawCE)
   {
      DeleteObjectIfExists(OBJ_BULL_CE);
      DeleteObjectIfExists(OBJ_BEAR_CE);
   }

   datetime endTime = DrawingEndTime();

   if(InpDrawFVG && gBull.valid)
   {
      DrawRectangleZone(OBJ_BULL_FVG,
                        gBull.startTime,
                        endTime,
                        gBull.low,
                        gBull.high,
                        clrPurple);

      if(InpDrawLabels)
      {
         DrawTextAtPrice(OBJ_BULL_TEXT,
                         "BULLISH M15 FVG",
                         endTime,
                         gBull.high,
                         clrWhite);
      }
   }
   else
   {
      DeleteObjectIfExists(OBJ_BULL_FVG);
      DeleteObjectIfExists(OBJ_BULL_TEXT);
   }

   if(InpDrawFVG && gBear.valid)
   {
      DrawRectangleZone(OBJ_BEAR_FVG,
                        gBear.startTime,
                        endTime,
                        gBear.low,
                        gBear.high,
                        clrPurple);

      if(InpDrawLabels)
      {
         DrawTextAtPrice(OBJ_BEAR_TEXT,
                         "BEARISH M15 FVG",
                         endTime,
                         gBear.high,
                         clrWhite);
      }
   }
   else
   {
      DeleteObjectIfExists(OBJ_BEAR_FVG);
      DeleteObjectIfExists(OBJ_BEAR_TEXT);
   }

   if(InpDrawCE && gBull.valid)
      DrawHorizontalPriceLine(OBJ_BULL_CE,gBull.ce,clrAqua,STYLE_DASH);
   else
      DeleteObjectIfExists(OBJ_BULL_CE);

   if(InpDrawCE && gBear.valid)
      DrawHorizontalPriceLine(OBJ_BEAR_CE,gBear.ce,clrAqua,STYLE_DASH);
   else
      DeleteObjectIfExists(OBJ_BEAR_CE);
}

void DrawOpenPositionLines()
{
   bool found = false;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      found = true;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);

      DrawHorizontalPriceLine(OBJ_ENTRY_LINE,open,clrWhite,STYLE_DOT);

      if(sl > 0.0)
         DrawHorizontalPriceLine(OBJ_SL_LINE,sl,clrRed,STYLE_DOT);
      else
         DeleteObjectIfExists(OBJ_SL_LINE);

      if(tp > 0.0)
         DrawHorizontalPriceLine(OBJ_TP_LINE,tp,clrLime,STYLE_DOT);
      else
         DeleteObjectIfExists(OBJ_TP_LINE);

      break;
   }

   if(!found)
   {
      DeleteObjectIfExists(OBJ_ENTRY_LINE);
      DeleteObjectIfExists(OBJ_SL_LINE);
      DeleteObjectIfExists(OBJ_TP_LINE);
   }
}

//====================================================================
// DASHBOARD - EACH LINE IS A DrawLabel OBJECT
//====================================================================
void DrawLabel(const string name,
               const string text,
               const int x,
               const int y,
               const int fontSize,
               const color clr,
               const bool bold=false)
{
   if(ObjectFind(0,name) < 0)
   {
      if(!ObjectCreate(0,name,OBJ_LABEL,0,0,0))
         return;
   }

   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontSize);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

string FVGStateText(const FVGZone &fvg)
{
   if(!fvg.valid)
      return("NONE");

   return(PriceToString(fvg.low) + " - " +
          PriceToString(fvg.high));
}

string PositionStateText()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double pnl = PositionGetDouble(POSITION_PROFIT);

      string side = (type == POSITION_TYPE_BUY ? "BUY" : "SELL");

      return(side + " " + DoubleToString(vol,2) +
             " | PnL " + DoubleToString(pnl,2));
   }

   return("NONE");
}

string EntryStatusText(const MqlTick &tick)
{
   if(!CanOpenTrade())
      return("BLOCKED - POSITION OPEN");

   if(gBull.valid && !IsTradeFVGAlreadyUsed(true,gBull.candleTime))
   {
      if(tick.ask > gBull.ce)
         return("WAIT BUY CE " + PriceToString(gBull.ce));
   }

   if(gBear.valid && !IsTradeFVGAlreadyUsed(false,gBear.candleTime))
   {
      if(tick.bid < gBear.ce)
         return("WAIT SELL CE " + PriceToString(gBear.ce));
   }

   return("WAIT");
}

void DrawDashboard()
{
   if(!InpShowDashboard)
   {
      DeleteObjectIfExists(DASH_TITLE);
      DeleteObjectIfExists(DASH_SYMBOL);
      DeleteObjectIfExists(DASH_BULL);
      DeleteObjectIfExists(DASH_BEAR);
      DeleteObjectIfExists(DASH_CE);
      DeleteObjectIfExists(DASH_POSITION);
      DeleteObjectIfExists(DASH_BALANCE);
      DeleteObjectIfExists(DASH_EQUITY);
      DeleteObjectIfExists(DASH_STATUS);
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   int x = InpDashboardX;
   int y = InpDashboardY;
   int lh = InpDashboardLineHeight;

   string bullText = "Bull FVG: " + FVGStateText(gBull);
   string bearText = "Bear FVG: " + FVGStateText(gBear);

   string ceText = "CE: ";
   if(gBull.valid)
      ceText += "B " + PriceToString(gBull.ce);
   else
      ceText += "B -";

   if(gBear.valid)
      ceText += " | ";
   else
      ceText += " | ";

   if(gBear.valid)
      ceText += "S " + PriceToString(gBear.ce);
   else
      ceText += "S -";

   DrawLabel(DASH_TITLE,
             "FVG CE AUTOTRADER",
             x,y,
             InpDashboardTextSize+1,
             clrGold,true);

   DrawLabel(DASH_SYMBOL,
             _Symbol + " | Setup M15 | Confirm M5",
             x,y+lh,
             InpDashboardTextSize,
             clrWhite);

   DrawLabel(DASH_BULL,
             bullText,
             x,y+(lh*2),
             InpDashboardTextSize,
             gBull.valid ? clrLime : clrSilver);

   DrawLabel(DASH_BEAR,
             bearText,
             x,y+(lh*3),
             InpDashboardTextSize,
             gBear.valid ? clrRed : clrSilver);

   DrawLabel(DASH_CE,
             ceText,
             x,y+(lh*4),
             InpDashboardTextSize,
             clrAqua);

   DrawLabel(DASH_POSITION,
             "Position: " + PositionStateText(),
             x,y+(lh*5),
             InpDashboardTextSize,
             clrWhite);

   DrawLabel(DASH_BALANCE,
             "Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2),
             x,y+(lh*6),
             InpDashboardTextSize,
             clrWhite);

   DrawLabel(DASH_EQUITY,
             "Equity:  " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2),
             x,y+(lh*7),
             InpDashboardTextSize,
             clrWhite);

   DrawLabel(DASH_STATUS,
             "Status: " + EntryStatusText(tick),
             x,y+(lh*8),
             InpDashboardTextSize,
             clrOrange);
}

//====================================================================
// M5 CONFIRMATION TIMEFRAME
//====================================================================
datetime CurrentM5BarTime()
{
   return(iTime(_Symbol,PERIOD_M5,0));
}

//====================================================================
// EVENTS
//====================================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   LoadTradedFVGState();

   ClearFVG(gBull);
   ClearFVG(gBear);

   MqlTick tick;
   if(SymbolInfoTick(_Symbol,tick))
   {
      gPrevBid = tick.bid;
      gPrevAsk = tick.ask;
   }

   DetectLatestFVGs(gBull,gBear);
   DrawFVGs();
   DrawOpenPositionLines();
   DrawDashboard();

   Print("FVG CE AutoTrader initialized on ",_Symbol,
         ". M15 setup / M5 CE confirmation.");

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteAllEAObjects();
   ChartRedraw(0);
}

void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   // Always refresh the latest confirmed M15 FVGs.
   DetectLatestFVGs(gBull,gBear);

   // Trade management has priority.
   ManageBreakEven();

   // M5 confirmation is evaluated live from the current M5 candle
   // high/low plus tick crossing of the M15 FVG CE.
   CurrentM5BarTime();

   CheckForEntries();

   DrawFVGs();
   DrawOpenPositionLines();
   DrawDashboard();

   gPrevBid = tick.bid;
   gPrevAsk = tick.ask;

   ChartRedraw(0);
}

//====================================================================
// TRADE TRANSACTION LOG
//====================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.symbol != _Symbol)
      return;

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      Print("Deal update | symbol=",trans.symbol,
            " | deal=",trans.deal,
            " | price=",PriceToString(trans.price),
            " | volume=",DoubleToString(trans.volume,2),
            " | type=",EnumToString((ENUM_DEAL_TYPE)trans.deal_type));
   }
}
//+------------------------------------------------------------------+
