//+------------------------------------------------------------------+
//| FVG_CE_Sniper.mq5                                                |
//| M15 Confirmed FVG -> M5 CE Touch -> Market Entry                 |
//|                                                                  |
//| Rules:                                                           |
//| 1) Detect latest confirmed M15 bullish/bearish 3-candle FVG.    |
//| 2) Use the FVG midpoint (CE) as the entry trigger.               |
//| 3) Buy bullish FVG / Sell bearish FVG.                           |
//| 4) SL behind the FVG.                                            |
//| 5) Move SL to BE at +40 pips.                                    |
//| 6) TP at +80 pips.                                               |
//| 7) One open EA position per symbol.                              |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "M15 confirmed FVG / M5 CE touch auto-trader"

input group "=== STRATEGY ==="
input ENUM_TIMEFRAMES InpSetupTF = PERIOD_M15;
input ENUM_TIMEFRAMES InpTriggerTF = PERIOD_M5;
input double InpPipSize = 0.10;             // XAUUSD: 1 pip = 0.10 by default
input double InpLots = 0.01;
input int    InpMaxSpreadPoints = 0;        // 0 = disabled
input int    InpSLBufferPips = 2;           // SL placed beyond FVG edge
input int    InpBETriggerPips = 40;
input int    InpTPPips = 80;
input ulong  InpMagic = 26081201;
input int    InpDeviationPoints = 30;

input group "=== FVG ==="
input int    InpMinFVGSizePoints = 1;

input group "=== CHART DRAWING ==="
input bool   InpDrawFVG = true;
input bool   InpDrawCE = true;
input bool   InpDrawTradeLevels = true;
input int    InpFVGForwardBars = 40;
input color  InpBullFVGColor = clrMediumPurple;
input color  InpBearFVGColor = clrMediumPurple;
input color  InpCEColor = clrWhite;
input color  InpEntryColor = clrDeepSkyBlue;
input color  InpSLColor = clrRed;
input color  InpTPColor = clrLime;

input group "=== DASHBOARD ==="
input bool   InpShowDashboard = true;
input int    InpDashboardX = 15;
input int    InpDashboardY = 25;
input int    InpDashboardFontSize = 9;
input int    InpDashboardLineHeight = 16;
input color  InpDashboardHeaderColor = clrGold;
input color  InpDashboardTextColor = clrWhite;
input color  InpDashboardBullColor = clrLime;
input color  InpDashboardBearColor = clrTomato;
input color  InpDashboardNeutralColor = clrSilver;

struct FVGData
{
   bool     valid;
   bool     bullish;
   datetime time1;
   datetime time2;
   datetime created;
   double   high;
   double   low;
   double   ce;
   double   size;
   bool     traded;
};

FVGData g_bull;
FVGData g_bear;

datetime g_lastSetupBar = 0;
ulong    g_lastTicket = 0;
double   g_lastEntry = 0.0;
double   g_lastSL = 0.0;
double   g_lastTP = 0.0;
string   g_status = "Waiting";
datetime g_lastTradeFVG = 0;
bool     g_beDone = false;

double g_prevTriggerBid = 0.0;
double g_prevTriggerAsk = 0.0;

string PREFIX = "FVGCE_";

//+------------------------------------------------------------------+
//| Price / symbol helpers                                           |
//+------------------------------------------------------------------+
double PipPrice()
{
   return InpPipSize;
}

double PipsToPrice(const double pips)
{
   return pips * PipPrice();
}

double NormalizePrice(const double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

double CurrentBid()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_BID);
}

double CurrentAsk()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_ASK);
}

bool SpreadOK()
{
   if(InpMaxSpreadPoints <= 0)
      return true;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return true;

   double spreadPoints = (CurrentAsk() - CurrentBid()) / point;
   return (spreadPoints <= InpMaxSpreadPoints);
}

double BrokerMinStopDistance()
{
   long stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return (double)stops * point;
}

//+------------------------------------------------------------------+
//| Position helpers                                                 |
//+------------------------------------------------------------------+
bool HasOurPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }

   return false;
}

ulong OurPositionTicket()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return ticket;
   }

   return 0;
}

//+------------------------------------------------------------------+
//| FVG                                                              |
//+------------------------------------------------------------------+
void ResetFVG(FVGData &fvg)
{
   fvg.valid = false;
   fvg.bullish = false;
   fvg.time1 = 0;
   fvg.time2 = 0;
   fvg.created = 0;
   fvg.high = 0.0;
   fvg.low = 0.0;
   fvg.ce = 0.0;
   fvg.size = 0.0;
   fvg.traded = false;
}

void SetFVG(FVGData &fvg,
            const bool bullish,
            const datetime time1,
            const datetime time2,
            const double high,
            const double low)
{
   fvg.valid = true;
   fvg.bullish = bullish;
   fvg.time1 = time1;
   fvg.time2 = time2;
   fvg.created = time2;
   fvg.high = NormalizePrice(MathMax(high, low));
   fvg.low = NormalizePrice(MathMin(high, low));
   fvg.ce = NormalizePrice((fvg.high + fvg.low) * 0.5);
   fvg.size = fvg.high - fvg.low;
   fvg.traded = false;
}

// A confirmed FVG is only accepted after the third candle has closed.
// Bullish: high of candle C1 < low of candle C3.
// Bearish: low of candle C1 > high of candle C3.
//
// With CopyRates starting at shift 1:
// r[0] = latest closed candle (C3)
// r[1] = middle candle (C2)
// r[2] = oldest candle in the 3-candle pattern (C1).
void ScanLatestConfirmedFVG()
{
   if(Bars(_Symbol, InpSetupTF) < 10)
      return;

   MqlRates r[3];
   ArraySetAsSeries(r, true);

   if(CopyRates(_Symbol, InpSetupTF, 1, 3, r) != 3)
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minSize = InpMinFVGSizePoints * point;

   // Bullish FVG
   if(r[2].high < r[0].low &&
      (r[0].low - r[2].high) >= minSize)
   {
      SetFVG(g_bull, true, r[2].time, r[0].time, r[0].low, r[2].high);
      g_status = "New bullish M15 FVG";
   }

   // Bearish FVG
   if(r[2].low > r[0].high &&
      (r[2].low - r[0].high) >= minSize)
   {
      SetFVG(g_bear, false, r[2].time, r[0].time, r[2].low, r[0].high);
      g_status = "New bearish M15 FVG";
   }
}

bool IsNewSetupBar()
{
   datetime t = iTime(_Symbol, InpSetupTF, 1);
   if(t == 0)
      return false;

   if(t != g_lastSetupBar)
   {
      g_lastSetupBar = t;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| M5 CE trigger                                                    |
//+------------------------------------------------------------------+
bool PriceTouchesCE(const FVGData &fvg, const double bid, const double ask)
{
   if(!fvg.valid)
      return false;

   // Bullish FVG: price retraces downward into the zone.
   if(fvg.bullish)
   {
      if(ask <= fvg.ce && ask >= fvg.low)
         return true;

      // Catch a fast tick that jumps across CE.
      if(g_prevTriggerAsk > fvg.ce && ask < fvg.ce)
         return true;

      return false;
   }

   // Bearish FVG: price retraces upward into the zone.
   if(bid >= fvg.ce && bid <= fvg.high)
      return true;

   // Catch a fast tick that jumps across CE.
   if(g_prevTriggerBid < fvg.ce && bid > fvg.ce)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Trading                                                          |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode()
{
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);

   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;

   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
}

bool ValidateStops(const ENUM_ORDER_TYPE type,
                   const double entry,
                   double &sl,
                   double &tp)
{
   double minDist = BrokerMinStopDistance();

   if(type == ORDER_TYPE_BUY)
   {
      if(sl >= entry || tp <= entry)
         return false;

      if(minDist > 0.0)
      {
         if((entry - sl) < minDist)
            sl = NormalizePrice(entry - minDist);

         if((tp - entry) < minDist)
            tp = NormalizePrice(entry + minDist);
      }
   }
   else
   {
      if(sl <= entry || tp >= entry)
         return false;

      if(minDist > 0.0)
      {
         if((sl - entry) < minDist)
            sl = NormalizePrice(entry + minDist);

         if((entry - tp) < minDist)
            tp = NormalizePrice(entry - minDist);
      }
   }

   return true;
}

bool SendMarketOrder(const ENUM_ORDER_TYPE type, FVGData &fvg)
{
   if(HasOurPosition())
   {
      g_status = "Position already open";
      return false;
   }

   if(!SpreadOK())
   {
      g_status = "Spread filter";
      return false;
   }

   double entry = (type == ORDER_TYPE_BUY ? CurrentAsk() : CurrentBid());
   double buffer = PipsToPrice(InpSLBufferPips);

   double sl = 0.0;
   double tp = 0.0;

   if(type == ORDER_TYPE_BUY)
   {
      // SL behind the lower edge of the bullish FVG.
      sl = fvg.low - buffer;

      // Fixed +80 pips from actual entry.
      tp = entry + PipsToPrice(InpTPPips);
   }
   else
   {
      // SL behind the upper edge of the bearish FVG.
      sl = fvg.high + buffer;

      // Fixed +80 pips from actual entry.
      tp = entry - PipsToPrice(InpTPPips);
   }

   entry = NormalizePrice(entry);
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);

   if(!ValidateStops(type, entry, sl, tp))
   {
      g_status = "Invalid SL/TP";
      return false;
   }

   MqlTradeRequest req;
   MqlTradeResult  res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = InpLots;
   req.type         = type;
   req.price        = entry;
   req.sl           = sl;
   req.tp           = tp;
   req.deviation    = InpDeviationPoints;
   req.magic        = InpMagic;
   req.comment      = "M15 FVG CE";
   req.type_filling = GetFillingMode();

   ResetLastError();

   if(!OrderSend(req, res))
   {
      g_status = "OrderSend failed: " + IntegerToString(GetLastError());
      return false;
   }

   if(res.retcode != TRADE_RETCODE_DONE &&
      res.retcode != TRADE_RETCODE_DONE_PARTIAL)
   {
      g_status = "Order rejected: " + IntegerToString((int)res.retcode);
      return false;
   }

   g_lastTicket = res.order;
   g_lastEntry = entry;
   g_lastSL = sl;
   g_lastTP = tp;
   g_lastTradeFVG = fvg.created;
   g_beDone = false;

   fvg.traded = true;

   if(type == ORDER_TYPE_BUY)
      g_status = "BUY @ bullish FVG CE";
   else
      g_status = "SELL @ bearish FVG CE";

   return true;
}

bool ModifyPositionSLTP(const ulong ticket,
                         const double sl,
                         const double tp)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   MqlTradeRequest req;
   MqlTradeResult  res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_SLTP;
   req.symbol   = PositionGetString(POSITION_SYMBOL);
   req.position = ticket;
   req.sl       = NormalizePrice(sl);
   req.tp       = NormalizePrice(tp);
   req.magic    = InpMagic;

   ResetLastError();

   if(!OrderSend(req, res))
      return false;

   return (res.retcode == TRADE_RETCODE_DONE);
}

void ManageOpenPosition()
{
   ulong ticket = OurPositionTicket();

   if(ticket == 0)
   {
      g_beDone = false;
      return;
   }

   if(!PositionSelectByTicket(ticket))
      return;

   long posType = PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);

   double current = (posType == POSITION_TYPE_BUY ?
                     CurrentBid() : CurrentAsk());

   double profitDistance =
      (posType == POSITION_TYPE_BUY ?
       current - openPrice :
       openPrice - current);

   if(!g_beDone &&
      profitDistance >= PipsToPrice(InpBETriggerPips))
   {
      double newSL = NormalizePrice(openPrice);
      bool shouldMove = false;

      if(posType == POSITION_TYPE_BUY)
      {
         if(currentSL == 0.0 || currentSL < newSL)
            shouldMove = true;
      }
      else
      {
         if(currentSL == 0.0 || currentSL > newSL)
            shouldMove = true;
      }

      if(shouldMove &&
         ModifyPositionSLTP(ticket, newSL, currentTP))
      {
         g_beDone = true;
         g_lastSL = newSL;
         g_status = "BE moved +40 pips";
      }
   }
}

void TryEntries()
{
   if(HasOurPosition())
      return;

   double bid = CurrentBid();
   double ask = CurrentAsk();

   bool bullTouch = PriceTouchesCE(g_bull, bid, ask);
   bool bearTouch = PriceTouchesCE(g_bear, bid, ask);

   // If both zones are touched on one tick, choose the closer CE.
   if(bullTouch && bearTouch)
   {
      double bullDistance = MathAbs(ask - g_bull.ce);
      double bearDistance = MathAbs(bid - g_bear.ce);

      if(bullDistance <= bearDistance)
         SendMarketOrder(ORDER_TYPE_BUY, g_bull);
      else
         SendMarketOrder(ORDER_TYPE_SELL, g_bear);

      return;
   }

   if(bullTouch && !g_bull.traded)
   {
      SendMarketOrder(ORDER_TYPE_BUY, g_bull);
      return;
   }

   if(bearTouch && !g_bear.traded)
   {
      SendMarketOrder(ORDER_TYPE_SELL, g_bear);
      return;
   }
}

//+------------------------------------------------------------------+
//| Chart drawing                                                    |
//+------------------------------------------------------------------+
void DeleteObjectIfExists(const string name)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
}

void DrawRectangle(const string name,
                   const datetime t1,
                   const datetime t2,
                   const double top,
                   const double bottom,
                   const color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bottom);
   else
   {
      ObjectMove(0, name, 0, t1, top);
      ObjectMove(0, name, 1, t2, bottom);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawHLine(const string name,
               const double price,
               const color clr,
               const ENUM_LINE_STYLE style,
               const int width)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);

   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawTextLabel(const string name,
                   const string text,
                   const datetime t,
                   const double price,
                   const color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   else
      ObjectMove(0, name, 0, t, price);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

datetime DrawingEndTime()
{
   int sec = PeriodSeconds(InpSetupTF);
   if(sec <= 0)
      sec = 900;

   return TimeCurrent() + sec * InpFVGForwardBars;
}

void DrawFVG(const FVGData &fvg,
             const string prefix,
             const color zoneColor)
{
   if(!fvg.valid || !InpDrawFVG)
   {
      DeleteObjectIfExists(prefix + "ZONE");
      DeleteObjectIfExists(prefix + "LABEL");
      DeleteObjectIfExists(prefix + "CE");
      DeleteObjectIfExists(prefix + "CE_LABEL");
      return;
   }

   datetime endTime = DrawingEndTime();

   DrawRectangle(prefix + "ZONE",
                 fvg.time1,
                 endTime,
                 fvg.high,
                 fvg.low,
                 zoneColor);

   string label =
      (fvg.bullish ? "BULLISH M15 FVG" : "BEARISH M15 FVG");

   DrawTextLabel(prefix + "LABEL",
                 label,
                 endTime,
                 fvg.high,
                 zoneColor);

   if(InpDrawCE)
   {
      DrawHLine(prefix + "CE",
                fvg.ce,
                InpCEColor,
                STYLE_DOT,
                1);

      DrawTextLabel(prefix + "CE_LABEL",
                    "CE " + DoubleToString(fvg.ce, _Digits),
                    endTime,
                    fvg.ce,
                    InpCEColor);
   }
   else
   {
      DeleteObjectIfExists(prefix + "CE");
      DeleteObjectIfExists(prefix + "CE_LABEL");
   }
}

void DrawTradeLevels()
{
   if(!InpDrawTradeLevels || !HasOurPosition())
   {
      DeleteObjectIfExists(PREFIX + "ENTRY");
      DeleteObjectIfExists(PREFIX + "SL");
      DeleteObjectIfExists(PREFIX + "TP");
      return;
   }

   ulong ticket = OurPositionTicket();

   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return;

   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);

   DrawHLine(PREFIX + "ENTRY",
             entry,
             InpEntryColor,
             STYLE_DASH,
             1);

   if(sl > 0.0)
      DrawHLine(PREFIX + "SL",
                sl,
                InpSLColor,
                STYLE_DASH,
                1);
   else
      DeleteObjectIfExists(PREFIX + "SL");

   if(tp > 0.0)
      DrawHLine(PREFIX + "TP",
                tp,
                InpTPColor,
                STYLE_DASH,
                1);
   else
      DeleteObjectIfExists(PREFIX + "TP");
}

//+------------------------------------------------------------------+
//| Dashboard: one DrawLabel per line                                |
//+------------------------------------------------------------------+
void DrawLabel(const string name,
               const string text,
               const int x,
               const int y,
               const color clr,
               const int fontSize,
               const bool bold=false)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT,
                   bold ? "Arial Bold" : "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DeleteDashboard()
{
   for(int i = 0; i < 20; ++i)
      DeleteObjectIfExists(PREFIX + "DASH_" + IntegerToString(i));
}

string FVGText(const FVGData &fvg)
{
   if(!fvg.valid)
      return "None";

   return (fvg.bullish ? "Bullish" : "Bearish") +
          " | CE " + DoubleToString(fvg.ce, _Digits);
}

color FVGColor(const FVGData &fvg)
{
   if(!fvg.valid)
      return InpDashboardNeutralColor;

   return fvg.bullish ?
          InpDashboardBullColor :
          InpDashboardBearColor;
}

void DrawDashboard()
{
   if(!InpShowDashboard)
   {
      DeleteDashboard();
      return;
   }

   int x = InpDashboardX;
   int y = InpDashboardY;
   int lh = InpDashboardLineHeight;
   int row = 0;

   DrawLabel(PREFIX + "DASH_0",
             "FVG CE SNIPER",
             x, y + lh*row++,
             InpDashboardHeaderColor,
             InpDashboardFontSize + 1,
             true);

   DrawLabel(PREFIX + "DASH_1",
             "Symbol: " + _Symbol,
             x, y + lh*row++,
             InpDashboardTextColor,
             InpDashboardFontSize);

   DrawLabel(PREFIX + "DASH_2",
             "M15 Bull FVG: " + FVGText(g_bull),
             x, y + lh*row++,
             FVGColor(g_bull),
             InpDashboardFontSize);

   DrawLabel(PREFIX + "DASH_3",
             "M15 Bear FVG: " + FVGText(g_bear),
             x, y + lh*row++,
             FVGColor(g_bear),
             InpDashboardFontSize);

   string trigger = "Waiting for CE";

   if(HasOurPosition())
      trigger = "IN TRADE";
   else if(g_bull.valid || g_bear.valid)
      trigger = "M5 CE monitor";

   DrawLabel(PREFIX + "DASH_4",
             "Trigger: " + trigger,
             x, y + lh*row++,
             InpDashboardTextColor,
             InpDashboardFontSize);

   DrawLabel(PREFIX + "DASH_5",
             "BE: +" + IntegerToString(InpBETriggerPips) + " pips",
             x, y + lh*row++,
             InpDashboardTextColor,
             InpDashboardFontSize);

   DrawLabel(PREFIX + "DASH_6",
             "TP: +" + IntegerToString(InpTPPips) + " pips",
             x, y + lh*row++,
             InpDashboardTextColor,
             InpDashboardFontSize);

   DrawLabel(PREFIX + "DASH_7",
             "Status: " + g_status,
             x, y + lh*row++,
             InpDashboardHeaderColor,
             InpDashboardFontSize);

   if(HasOurPosition())
   {
      ulong ticket = OurPositionTicket();

      if(PositionSelectByTicket(ticket))
      {
         long type = PositionGetInteger(POSITION_TYPE);
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur = (type == POSITION_TYPE_BUY ?
                       CurrentBid() : CurrentAsk());

         double pips =
            (type == POSITION_TYPE_BUY ?
             (cur-open) :
             (open-cur)) / PipPrice();

         DrawLabel(PREFIX + "DASH_8",
                   "Float: " + DoubleToString(pips, 1) + " pips",
                   x, y + lh*row++,
                   pips >= 0.0 ?
                   InpDashboardBullColor :
                   InpDashboardBearColor,
                   InpDashboardFontSize);
      }
   }
   else
   {
      DeleteObjectIfExists(PREFIX + "DASH_8");
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpPipSize <= 0.0)
   {
      Print("ERROR: InpPipSize must be greater than zero.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpLots <= 0.0)
   {
      Print("ERROR: InpLots must be greater than zero.");
      return INIT_PARAMETERS_INCORRECT;
   }

   ResetFVG(g_bull);
   ResetFVG(g_bear);

   g_lastSetupBar = iTime(_Symbol, InpSetupTF, 1);

   ScanLatestConfirmedFVG();

   g_status = "Ready - M5 CE monitor";

   DrawFVG(g_bull,
           PREFIX + "BULL_",
           InpBullFVGColor);

   DrawFVG(g_bear,
           PREFIX + "BEAR_",
           InpBearFVGColor);

   DrawDashboard();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteObjectIfExists(PREFIX + "BULL_ZONE");
   DeleteObjectIfExists(PREFIX + "BULL_LABEL");
   DeleteObjectIfExists(PREFIX + "BULL_CE");
   DeleteObjectIfExists(PREFIX + "BULL_CE_LABEL");

   DeleteObjectIfExists(PREFIX + "BEAR_ZONE");
   DeleteObjectIfExists(PREFIX + "BEAR_LABEL");
   DeleteObjectIfExists(PREFIX + "BEAR_CE");
   DeleteObjectIfExists(PREFIX + "BEAR_CE_LABEL");

   DeleteObjectIfExists(PREFIX + "ENTRY");
   DeleteObjectIfExists(PREFIX + "SL");
   DeleteObjectIfExists(PREFIX + "TP");

   DeleteDashboard();

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // A new closed M15 candle can confirm a new FVG.
   if(IsNewSetupBar())
   {
      ScanLatestConfirmedFVG();

      DrawFVG(g_bull,
              PREFIX + "BULL_",
              InpBullFVGColor);

      DrawFVG(g_bear,
              PREFIX + "BEAR_",
              InpBearFVGColor);
   }

   // Trade management is tick-by-tick.
   ManageOpenPosition();

   // The M5 confirmation is the live price reaching the M15 FVG CE.
   TryEntries();

   DrawTradeLevels();
   DrawDashboard();

   g_prevTriggerBid = CurrentBid();
   g_prevTriggerAsk = CurrentAsk();
}
//+------------------------------------------------------------------+
