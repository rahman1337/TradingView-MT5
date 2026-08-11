//+------------------------------------------------------------------+
//|                                             FVG_Sniper_JOAT_EA.mq5
//|                                             Single-file MT5 EA
//|
//| FVG Sniper [JOAT] conversion
//| Original concept:
//| Bullish FVG = Low > High[2]
//| Bearish FVG = High < Low[2]
//|
//| TIMEFRAMES
//| HTF = H1
//| LTF = M5
//|
//| TRADE MANAGEMENT
//| BE       = +0.30R
//| SL -> TP1 = +1.30R
//| SL -> TP2 = +2.30R
//| Final exit = TP3 / SL / Max Trade Bars
//|
//| SINGLE FILE - NO EXTERNAL .MQH FILES
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "FVG Sniper [JOAT] single-file MT5 EA"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_MODE
{
   SIGNAL_REJECTION_ONLY = 0,
   SIGNAL_IFVG_ONLY      = 1,
   SIGNAL_REJECTION_IFVG = 2
};

enum ENUM_STOP_MODE
{
   STOP_GAP_PROTECTED = 0,
   STOP_ATR           = 1
};

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+

//====================================================================
// ENGINE
//====================================================================
input group "=== 01 · ENGINE ==="

input bool InpAllowBullFVG = true;
input bool InpAllowBearFVG = true;

input ENUM_SIGNAL_MODE InpSignalMode = SIGNAL_REJECTION_IFVG;

input int InpMaxVisibleGaps = 14;
input int InpGapLifetimeBars = 220;
input int InpGapExtensionBars = 12;

//====================================================================
// FILTERS
//====================================================================
input group "=== 02 · FILTERS ==="

input int    InpATRLength = 14;
input double InpMinGapATR = 0.25;
input double InpMinBodyRatio = 0.45;
input double InpMinSignalGrade = 4.0;

input bool InpUseHTFBias = true;

// EXACT ADDITION:
// HTF = H1
input ENUM_TIMEFRAMES InpHTF = PERIOD_H1;

input int InpHTFEMALength = 50;

input bool InpRequireDirectionalClose = true;

//====================================================================
// TRADE MODEL
//====================================================================
input group "=== 03 · TRADE MODEL ==="

input ENUM_STOP_MODE InpStopMode = STOP_GAP_PROTECTED;

input double InpGapStopBufferATR = 0.20;
input double InpATRStopDistance = 1.50;

input double InpMinRiskATR = 0.40;
input double InpMaxRiskATR = 4.00;

input double InpTP1R = 1.0;
input double InpTP2R = 2.0;
input double InpTP3R = 3.0;

input int InpMaxTradeBars = 120;

//====================================================================
// ADDITIONAL TRADE MANAGEMENT
//====================================================================
input group "=== 04 · TRADE MANAGEMENT ==="

// BE when price reaches R0.3
input double InpBETriggerR = 0.30;

// Move SL to TP1 when price reaches TP1.3
input double InpTP1TrailTriggerR = 1.30;

// Move SL to TP2 when price reaches TP2.3
input double InpTP2TrailTriggerR = 2.30;

input int InpTradeDeviationPoints = 20;

//====================================================================
// RISK / LOT
//====================================================================
input group "=== 05 · LOT SIZE ==="

input bool   InpUseRiskPercent = true;
input double InpRiskPercent = 1.0;
input double InpFixedLot = 0.01;

//====================================================================
// VISUALS
//====================================================================
input group "=== 06 · VISUALS ==="

input bool InpShowGapBoxes = true;
input bool InpShowGapMidline = false;
input bool InpShowIFVG = true;

input bool InpShowSignalLabels = true;
input bool InpShowGrade = true;

input bool InpShowTradeZones = true;
input bool InpShowTradeLines = true;
input bool InpShowLevelLabels = true;
input bool InpShowExitLabels = true;

input bool InpShowVWAP = false;
input bool InpColorCandles = false;

input int InpBoxTransparency = 86;
input int InpProjectionBars = 8;
input int InpMaxDrawnTrades = 20;

//====================================================================
// DASHBOARD
//====================================================================
input group "=== 07 · DASHBOARD ==="

input bool InpShowDashboard = true;

input int InpDashboardX = 20;
input int InpDashboardY = 25;

input int InpDashboardTextSize = 9;
input int InpDashboardLineHeight = 17;

//====================================================================
// EA
//====================================================================
input group "=== 08 · EA SETTINGS ==="

input ulong InpMagicNumber = 26081101;

input bool InpOneTradeOnly = true;

input bool InpTradeLong = true;
input bool InpTradeShort = true;

input bool InpRequireM5Chart = true;

//+------------------------------------------------------------------+
//| COLORS                                                           |
//+------------------------------------------------------------------+

color COL_BULL   = C'38,166,154';
color COL_BEAR   = C'239,83,80';
color COL_IFVG   = C'255,179,0';

color COL_CHROME = C'198,214,224';
color COL_RISK   = C'230,45,60';

color COL_WHITE  = clrWhite;
color COL_GRAY   = C'150,156,168';

color COL_DARK   = C'16,18,24';
color COL_DARK2  = C'26,29,37';

//+------------------------------------------------------------------+
//| CONSTANTS                                                        |
//+------------------------------------------------------------------+

#define PREFIX "FVGJOAT_"

//+------------------------------------------------------------------+
//| FVG STRUCTURE                                                    |
//+------------------------------------------------------------------+

struct FVGGap
{
   double top;
   double bottom;

   int direction;

   datetime bornTime;
   int bornBar;

   double grade;

   double extreme;
   double fillPct;

   bool mitigated;
   bool inverted;
   bool reacted;

   string boxName;
   string midName;
};

//+------------------------------------------------------------------+
//| GLOBAL STATE                                                     |
//+------------------------------------------------------------------+

FVGGap Gaps[];

int g_totalBull = 0;
int g_totalBear = 0;
int g_totalInv  = 0;

int g_lastFlipDir = 0;
datetime g_lastFlipTime = 0;

bool g_buySignal = false;
bool g_sellSignal = false;

string g_signalTag = "";

double g_signalTop = 0.0;
double g_signalBottom = 0.0;
double g_signalGrade = 0.0;

//+------------------------------------------------------------------+
//| TRADE STATE                                                      |
//+------------------------------------------------------------------+

bool g_tradeActive = false;

int g_tradeSide = 0;

datetime g_tradeOpenTime = 0;

double g_entry = 0.0;
double g_stop = 0.0;

double g_tp1 = 0.0;
double g_tp2 = 0.0;
double g_tp3 = 0.0;

double g_risk = 0.0;

bool g_beDone = false;
bool g_tp1TrailDone = false;
bool g_tp2TrailDone = false;

ulong g_positionTicket = 0;

//+------------------------------------------------------------------+
//| INDICATOR HANDLES                                                |
//+------------------------------------------------------------------+

int g_atrHandle = INVALID_HANDLE;
int g_emaHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| BAR STATE                                                        |
//+------------------------------------------------------------------+

datetime g_lastM5Bar = 0;

//+------------------------------------------------------------------+
//| OBJECT COUNTER                                                   |
//+------------------------------------------------------------------+

int g_objectCounter = 0;

//+------------------------------------------------------------------+
//| HELPER: UNIQUE NAME                                              |
//+------------------------------------------------------------------+

string UniqueName(string prefix)
{
   g_objectCounter++;

   return PREFIX +
          prefix +
          "_" +
          IntegerToString((int)TimeLocal()) +
          "_" +
          IntegerToString(g_objectCounter);
}

//+------------------------------------------------------------------+
//| HELPER: STARS                                                    |
//+------------------------------------------------------------------+

string GradeStars(double grade)
{
   if(grade >= 9.0)
      return "★★★★★";

   if(grade >= 7.0)
      return "★★★★";

   if(grade >= 5.0)
      return "★★★";

   if(grade >= 3.0)
      return "★★";

   return "★";
}

//+------------------------------------------------------------------+
//| HELPER: PRICE NORMALIZATION                                      |
//+------------------------------------------------------------------+

double NormalizePrice(double price)
{
   return NormalizeDouble(price, _Digits);
}

//+------------------------------------------------------------------+
//| HELPER: POINT VALUE                                              |
//+------------------------------------------------------------------+

double PointValue()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

//+------------------------------------------------------------------+
//| HELPER: ATR                                                      |
//+------------------------------------------------------------------+

double GetATR(int shift = 1)
{
   if(g_atrHandle == INVALID_HANDLE)
      return 0.0;

   double buffer[];

   ArraySetAsSeries(buffer, true);

   if(CopyBuffer(g_atrHandle, 0, shift, 1, buffer) != 1)
      return 0.0;

   return buffer[0];
}

//+------------------------------------------------------------------+
//| HELPER: HTF BIAS                                                 |
//+------------------------------------------------------------------+

int GetHTFBias()
{
   if(!InpUseHTFBias)
      return 0;

   if(g_emaHandle == INVALID_HANDLE)
      return 0;

   double ema[];

   ArraySetAsSeries(ema, true);

   if(CopyBuffer(g_emaHandle, 0, 1, 1, ema) != 1)
      return 0;

   MqlRates htfRates[];

   ArraySetAsSeries(htfRates, true);

   if(CopyRates(_Symbol, InpHTF, 1, 1, htfRates) != 1)
      return 0;

   if(htfRates[0].close > ema[0])
      return 1;

   if(htfRates[0].close < ema[0])
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| HELPER: DELETE OBJECT                                            |
//+------------------------------------------------------------------+

void DeleteObjectSafe(string name)
{
   if(name == "")
      return;

   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
}

//+------------------------------------------------------------------+
//| DELETE FVG OBJECTS                                               |
//+------------------------------------------------------------------+

void DeleteFVGObjects(FVGGap &f)
{
   DeleteObjectSafe(f.boxName);
   DeleteObjectSafe(f.midName);

   f.boxName = "";
   f.midName = "";
}

//+------------------------------------------------------------------+
//| DRAW FVG                                                         |
//+------------------------------------------------------------------+

void DrawFVG(FVGGap &f)
{
   if(!InpShowGapBoxes)
      return;

   color baseColor = f.direction == 1 ? COL_BULL : COL_BEAR;

   string boxName = UniqueName("FVG_BOX");

   datetime rightTime =
      f.bornTime +
      PeriodSeconds(PERIOD_M5) * InpGapExtensionBars;

   if(ObjectCreate(0,
                   boxName,
                   OBJ_RECTANGLE,
                   0,
                   f.bornTime,
                   f.top,
                   rightTime,
                   f.bottom))
   {
      ObjectSetInteger(0, boxName, OBJPROP_COLOR, baseColor);
      ObjectSetInteger(0, boxName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, boxName, OBJPROP_WIDTH, 1);

      ObjectSetInteger(0,
                       boxName,
                       OBJPROP_FILL,
                       true);

      ObjectSetInteger(0,
                       boxName,
                       OBJPROP_BACK,
                       true);

      f.boxName = boxName;
   }

   if(InpShowGapMidline)
   {
      string midName = UniqueName("FVG_MID");

      double mid = (f.top + f.bottom) / 2.0;

      if(ObjectCreate(0,
                      midName,
                      OBJ_TREND,
                      0,
                      f.bornTime,
                      mid,
                      rightTime,
                      mid))
      {
         ObjectSetInteger(0,
                          midName,
                          OBJPROP_COLOR,
                          baseColor);

         ObjectSetInteger(0,
                          midName,
                          OBJPROP_STYLE,
                          STYLE_DOT);

         ObjectSetInteger(0,
                          midName,
                          OBJPROP_WIDTH,
                          1);

         ObjectSetInteger(0,
                          midName,
                          OBJPROP_RAY_RIGHT,
                          false);

         f.midName = midName;
      }
   }
}

//+------------------------------------------------------------------+
//| RESTYLE IFVG                                                     |
//+------------------------------------------------------------------+

void RestyleIFVG(FVGGap &f)
{
   if(!InpShowIFVG)
      return;

   if(f.boxName != "")
   {
      if(ObjectFind(0, f.boxName) >= 0)
      {
         ObjectSetInteger(0,
                          f.boxName,
                          OBJPROP_COLOR,
                          COL_IFVG);

         ObjectSetInteger(0,
                          f.boxName,
                          OBJPROP_STYLE,
                          STYLE_DASH);
      }
   }

   if(f.midName != "")
   {
      if(ObjectFind(0, f.midName) >= 0)
      {
         ObjectSetInteger(0,
                          f.midName,
                          OBJPROP_COLOR,
                          COL_IFVG);

         ObjectSetInteger(0,
                          f.midName,
                          OBJPROP_STYLE,
                          STYLE_DASH);
      }
   }
}

//+------------------------------------------------------------------+
//| UPDATE FVG OBJECT                                                |
//+------------------------------------------------------------------+

void UpdateFVGDrawing(FVGGap &f)
{
   if(f.boxName != "")
   {
      if(ObjectFind(0, f.boxName) >= 0)
      {
         datetime rightTime =
            iTime(_Symbol,
                  PERIOD_M5,
                  0) +
            PeriodSeconds(PERIOD_M5) *
            InpGapExtensionBars;

         ObjectMove(0,
                    f.boxName,
                    1,
                    rightTime,
                    f.bottom);

         ObjectMove(0,
                    f.boxName,
                    0,
                    f.bornTime,
                    f.top);
      }
   }

   if(f.midName != "")
   {
      if(ObjectFind(0, f.midName) >= 0)
      {
         double mid = (f.top + f.bottom) / 2.0;

         datetime rightTime =
            iTime(_Symbol,
                  PERIOD_M5,
                  0) +
            PeriodSeconds(PERIOD_M5) *
            InpGapExtensionBars;

         ObjectMove(0,
                    f.midName,
                    1,
                    rightTime,
                    mid);
      }
   }
}

//+------------------------------------------------------------------+
//| DRAW TEXT LABEL                                                  |
//+------------------------------------------------------------------+

void DrawTextLabel(string name,
                   string text,
                   datetime timeValue,
                   double price,
                   color clr,
                   ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_LOWER,
                   int size = 8)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   if(!ObjectCreate(0,
                    name,
                    OBJ_TEXT,
                    0,
                    timeValue,
                    price))
      return;

   ObjectSetString(0,
                   name,
                   OBJPROP_TEXT,
                   text);

   ObjectSetString(0,
                   name,
                   OBJPROP_FONT,
                   "Arial");

   ObjectSetInteger(0,
                    name,
                    OBJPROP_FONTSIZE,
                    size);

   ObjectSetInteger(0,
                    name,
                    OBJPROP_COLOR,
                    clr);

   ObjectSetInteger(0,
                    name,
                    OBJPROP_ANCHOR,
                    anchor);

   ObjectSetInteger(0,
                    name,
                    OBJPROP_BACK,
                    false);
}

//+------------------------------------------------------------------+
//| DRAW SIGNAL                                                      |
//+------------------------------------------------------------------+

void DrawSignal(int direction,
                double grade,
                string tag)
{
   if(!InpShowSignalLabels)
      return;

   double atr = GetATR(1);

   if(atr <= 0)
      atr = PointValue() * 100;

   MqlRates rates[];

   ArraySetAsSeries(rates, true);

   if(CopyRates(_Symbol,
                PERIOD_M5,
                1,
                1,
                rates) != 1)
      return;

   datetime t = rates[0].time;

   double price;

   if(direction == 1)
      price = rates[0].low - atr * 0.6;
   else
      price = rates[0].high + atr * 0.6;

   string name = UniqueName("SIGNAL");

   string text =
      direction == 1 ? "BUY" : "SELL";

   if(InpShowGrade)
   {
      text += "\n";
      text += GradeStars(grade);
      text += " ";
      text += DoubleToString(grade, 1);
      text += "/10";
   }

   DrawTextLabel(name,
                 text,
                 t,
                 price,
                 direction == 1 ? COL_BULL : COL_BEAR,
                 direction == 1 ?
                 ANCHOR_LEFT_LOWER :
                 ANCHOR_LEFT_UPPER,
                 9);
}

//+------------------------------------------------------------------+
//| DRAW HORIZONTAL PRICE LINE                                       |
//+------------------------------------------------------------------+

string DrawPriceLine(string prefix,
                     double price,
                     color clr,
                     ENUM_LINE_STYLE style,
                     int width)
{
   string name = UniqueName(prefix);

   datetime t1 = iTime(_Symbol, PERIOD_M5, 0);

   datetime t2 =
      t1 +
      PeriodSeconds(PERIOD_M5) *
      InpProjectionBars;

   if(ObjectCreate(0,
                   name,
                   OBJ_TREND,
                   0,
                   t1,
                   price,
                   t2,
                   price))
   {
      ObjectSetInteger(0,
                       name,
                       OBJPROP_COLOR,
                       clr);

      ObjectSetInteger(0,
                       name,
                       OBJPROP_STYLE,
                       style);

      ObjectSetInteger(0,
                       name,
                       OBJPROP_WIDTH,
                       width);

      ObjectSetInteger(0,
                       name,
                       OBJPROP_RAY_RIGHT,
                       false);
   }

   return name;
}

//+------------------------------------------------------------------+
//| DRAW TRADE LEVEL LABEL                                           |
//+------------------------------------------------------------------+

string DrawTradeLevelLabel(string text,
                           double price,
                           color clr)
{
   string name = UniqueName("LEVEL");

   datetime t =
      iTime(_Symbol,
            PERIOD_M5,
            0) +
      PeriodSeconds(PERIOD_M5) *
      InpProjectionBars;

   DrawTextLabel(name,
                 text,
                 t,
                 price,
                 clr,
                 ANCHOR_LEFT,
                 8);

   return name;
}

//+------------------------------------------------------------------+
//| DRAW TRADE ZONE                                                  |
//+------------------------------------------------------------------+

string DrawZone(string prefix,
                double price1,
                double price2,
                color clr)
{
   string name = UniqueName(prefix);

   datetime left =
      iTime(_Symbol,
            PERIOD_M5,
            0);

   datetime right =
      left +
      PeriodSeconds(PERIOD_M5) *
      InpProjectionBars;

   double top = MathMax(price1, price2);
   double bot = MathMin(price1, price2);

   if(ObjectCreate(0,
                   name,
                   OBJ_RECTANGLE,
                   0,
                   left,
                   top,
                   right,
                   bot))
   {
      ObjectSetInteger(0,
                       name,
                       OBJPROP_COLOR,
                       clr);

      ObjectSetInteger(0,
                       name,
                       OBJPROP_FILL,
                       true);

      ObjectSetInteger(0,
                       name,
                       OBJPROP_BACK,
                       true);

      ObjectSetInteger(0,
                       name,
                       OBJPROP_WIDTH,
                       1);
   }

   return name;
}

//+------------------------------------------------------------------+
//| ACTIVE TRADE DRAWING NAMES                                       |
//+------------------------------------------------------------------+

string g_entryLineName = "";
string g_slLineName = "";
string g_tp1LineName = "";
string g_tp2LineName = "";
string g_tp3LineName = "";

string g_targetZoneName = "";
string g_riskZoneName = "";

string g_entryLabelName = "";
string g_slLabelName = "";
string g_tp1LabelName = "";
string g_tp2LabelName = "";
string g_tp3LabelName = "";

//+------------------------------------------------------------------+
//| DRAW ACTIVE TRADE                                               |
//+------------------------------------------------------------------+

void DrawActiveTrade()
{
   DeleteActiveTradeObjects();

   if(!InpShowTradeLines &&
      !InpShowTradeZones &&
      !InpShowLevelLabels)
      return;

   if(InpShowTradeLines)
   {
      g_entryLineName =
         DrawPriceLine("ENTRY",
                       g_entry,
                       COL_CHROME,
                       STYLE_SOLID,
                       2);

      g_slLineName =
         DrawPriceLine("SL",
                       g_stop,
                       COL_RISK,
                       STYLE_DASH,
                       1);

      g_tp1LineName =
         DrawPriceLine("TP1",
                       g_tp1,
                       COL_BULL,
                       STYLE_SOLID,
                       1);

      g_tp2LineName =
         DrawPriceLine("TP2",
                       g_tp2,
                       COL_BULL,
                       STYLE_DOT,
                       1);

      g_tp3LineName =
         DrawPriceLine("TP3",
                       g_tp3,
                       COL_BULL,
                       STYLE_DOT,
                       1);
   }

   if(InpShowTradeZones)
   {
      double targetTop =
         g_tradeSide == 1 ?
         g_tp3 :
         g_entry;

      double targetBottom =
         g_tradeSide == 1 ?
         g_entry :
         g_tp3;

      g_targetZoneName =
         DrawZone("TARGET",
                  targetTop,
                  targetBottom,
                  COL_BULL);

      double riskTop =
         g_tradeSide == 1 ?
         g_entry :
         g_stop;

      double riskBottom =
         g_tradeSide == 1 ?
         g_stop :
         g_entry;

      g_riskZoneName =
         DrawZone("RISK",
                  riskTop,
                  riskBottom,
                  COL_RISK);
   }

   if(InpShowLevelLabels)
   {
      g_entryLabelName =
         DrawTradeLevelLabel(
            g_tradeSide == 1 ?
            "LONG @ " + DoubleToString(g_entry, _Digits) :
            "SHORT @ " + DoubleToString(g_entry, _Digits),
            g_entry,
            COL_CHROME);

      g_slLabelName =
         DrawTradeLevelLabel(
            "SL @ " +
            DoubleToString(g_stop, _Digits),
            g_stop,
            COL_RISK);

      g_tp1LabelName =
         DrawTradeLevelLabel(
            "TP1 " +
            DoubleToString(InpTP1R, 1) +
            "R",
            g_tp1,
            COL_BULL);

      g_tp2LabelName =
         DrawTradeLevelLabel(
            "TP2 " +
            DoubleToString(InpTP2R, 1) +
            "R",
            g_tp2,
            COL_BULL);

      g_tp3LabelName =
         DrawTradeLevelLabel(
            "TP3 " +
            DoubleToString(InpTP3R, 1) +
            "R",
            g_tp3,
            COL_BULL);
   }
}

//+------------------------------------------------------------------+
//| DELETE ACTIVE TRADE OBJECTS                                      |
//+------------------------------------------------------------------+

void DeleteActiveTradeObjects()
{
   DeleteObjectSafe(g_entryLineName);
   DeleteObjectSafe(g_slLineName);
   DeleteObjectSafe(g_tp1LineName);
   DeleteObjectSafe(g_tp2LineName);
   DeleteObjectSafe(g_tp3LineName);

   DeleteObjectSafe(g_targetZoneName);
   DeleteObjectSafe(g_riskZoneName);

   DeleteObjectSafe(g_entryLabelName);
   DeleteObjectSafe(g_slLabelName);
   DeleteObjectSafe(g_tp1LabelName);
   DeleteObjectSafe(g_tp2LabelName);
   DeleteObjectSafe(g_tp3LabelName);

   g_entryLineName = "";
   g_slLineName = "";
   g_tp1LineName = "";
   g_tp2LineName = "";
   g_tp3LineName = "";

   g_targetZoneName = "";
   g_riskZoneName = "";

   g_entryLabelName = "";
   g_slLabelName = "";
   g_tp1LabelName = "";
   g_tp2LabelName = "";
   g_tp3LabelName = "";
}

//+------------------------------------------------------------------+
//| DRAW EXIT                                                        |
//+------------------------------------------------------------------+

void DrawExitLabel(string text,
                   double price,
                   color clr)
{
   if(!InpShowExitLabels)
      return;

   string name = UniqueName("EXIT");

   datetime t = iTime(_Symbol,
                      PERIOD_M5,
                      0);

   DrawTextLabel(name,
                 text,
                 t,
                 price,
                 clr,
                 ANCHOR_LEFT_LOWER,
                 9);
}

//+------------------------------------------------------------------+
//| DASHBOARD LABEL                                                  |
//+------------------------------------------------------------------+

void DrawLabel(string name,
               string text,
               int x,
               int y,
               int fontSize,
               color clr,
               bool bold = false)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0,
                       name,
                       OBJ_LABEL,
                       0,
                       0,
                       0))
         return;
   }

   ObjectSetInteger(0,
                    name,
                    OBJPROP_CORNER,
                    CORNER_LEFT_UPPER);

   ObjectSetInteger(0,
                    name,
                    OBJPROP_XDISTANCE,
                    x);

   ObjectSetInteger(0,
                    name,
                    OBJPROP_YDISTANCE,
                    y);

   ObjectSetString(0,
                   name,
                   OBJPROP_TEXT,
                   text);

   ObjectSetString(0,
                   name,
                   OBJPROP_FONT,
                   bold ? "Arial Bold" : "Arial");

   ObjectSetInteger(0,
                    name,
                    OBJPROP_FONTSIZE,
                    fontSize);

   ObjectSetInteger(0,
                    name,
                    OBJPROP_COLOR,
                    clr);

   ObjectSetInteger(0,
                    name,
                    OBJPROP_SELECTABLE,
                    false);

   ObjectSetInteger(0,
                    name,
                    OBJPROP_HIDDEN,
                    true);
}

//+------------------------------------------------------------------+
//| DASHBOARD                                                        |
//+------------------------------------------------------------------+

void UpdateDashboard()
{
   if(!InpShowDashboard)
      return;

   int x = InpDashboardX;
   int y = InpDashboardY;

   int lh = InpDashboardLineHeight;
   int fs = InpDashboardTextSize;

   string prefix = PREFIX + "DASH_";

   int bias = GetHTFBias();

   string biasText =
      bias > 0 ?
      "BULLISH" :
      bias < 0 ?
      "BEARISH" :
      "NEUTRAL";

   color biasColor =
      bias > 0 ?
      COL_BULL :
      bias < 0 ?
      COL_BEAR :
      COL_GRAY;

   int activeBull = 0;
   int activeBear = 0;

   double bestGrade = 0.0;
   int bestDir = 0;

   double nearestPrice = 0.0;
   double nearestDistance = DBL_MAX;
   double nearestFill = 0.0;
   int nearestDir = 0;

   double bid = SymbolInfoDouble(_Symbol,
                                 SYMBOL_BID);

   for(int i = 0; i < ArraySize(Gaps); i++)
   {
      FVGGap &f = Gaps[i];

      if(f.inverted || f.mitigated)
         continue;

      if(f.direction == 1)
         activeBull++;
      else
         activeBear++;

      if(f.grade > bestGrade)
      {
         bestGrade = f.grade;
         bestDir = f.direction;
      }

      double mid =
         (f.top + f.bottom) / 2.0;

      double dist =
         MathAbs(bid - mid);

      if(dist < nearestDistance)
      {
         nearestDistance = dist;
         nearestPrice = mid;
         nearestFill = f.fillPct;
         nearestDir = f.direction;
      }
   }

   double balance =
      AccountInfoDouble(ACCOUNT_BALANCE);

   double equity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   double floating =
      AccountInfoDouble(ACCOUNT_PROFIT);

   string tradeText = "—";

   color tradeColor = COL_GRAY;

   if(g_tradeActive)
   {
      tradeText =
         g_tradeSide == 1 ?
         "LONG @ " +
         DoubleToString(g_entry, _Digits) :
         "SHORT @ " +
         DoubleToString(g_entry, _Digits);

      tradeColor =
         g_tradeSide == 1 ?
         COL_BULL :
         COL_BEAR;
   }

   string signalText = "—";
   color signalColor = COL_GRAY;

   if(g_buySignal)
   {
      signalText = "BUY " + g_signalTag;
      signalColor = COL_BULL;
   }
   else
   if(g_sellSignal)
   {
      signalText = "SELL " + g_signalTag;
      signalColor = COL_BEAR;
   }

   int row = 0;

   DrawLabel(prefix + "TITLE",
             "FVG SNIPER [JOAT]",
             x,
             y + row++ * lh,
             fs + 2,
             COL_CHROME,
             true);

   DrawLabel(prefix + "BIAS",
             "HTF Bias : " + biasText,
             x,
             y + row++ * lh,
             fs,
             biasColor,
             true);

   DrawLabel(prefix + "BULL",
             "Active Bull FVG : " +
             IntegerToString(activeBull),
             x,
             y + row++ * lh,
             fs,
             COL_BULL);

   DrawLabel(prefix + "BEAR",
             "Active Bear FVG : " +
             IntegerToString(activeBear),
             x,
             y + row++ * lh,
             fs,
             COL_BEAR);

   string nearestText = "Nearest Gap : —";

   if(nearestDistance != DBL_MAX)
   {
      nearestText =
         "Nearest Gap : " +
         DoubleToString(nearestPrice, _Digits) +
         (nearestDir == 1 ? " ▲" : " ▼");
   }

   DrawLabel(prefix + "NEAR",
             nearestText,
             x,
             y + row++ * lh,
             fs,
             COL_WHITE);

   DrawLabel(prefix + "FILL",
             "Nearest Fill : " +
             (nearestDistance == DBL_MAX ?
              "—" :
              DoubleToString(nearestFill * 100.0, 0) + "%"),
             x,
             y + row++ * lh,
             fs,
             COL_WHITE);

   DrawLabel(prefix + "GRADE",
             "Strongest Gap : " +
             (bestGrade > 0 ?
              GradeStars(bestGrade) +
              " " +
              DoubleToString(bestGrade, 1) :
              "—"),
             x,
             y + row++ * lh,
             fs,
             bestDir == 1 ?
             COL_BULL :
             bestDir == -1 ?
             COL_BEAR :
             COL_WHITE);

   DrawLabel(prefix + "FLIP",
             "Last IFVG : " +
             (g_lastFlipDir == 1 ?
              "▲ Bull" :
              g_lastFlipDir == -1 ?
              "▼ Bear" :
              "—"),
             x,
             y + row++ * lh,
             fs,
             g_lastFlipDir == 1 ?
             COL_BULL :
             g_lastFlipDir == -1 ?
             COL_BEAR :
             COL_GRAY);

   DrawLabel(prefix + "SIGNAL",
             "Signal : " + signalText,
             x,
             y + row++ * lh,
             fs,
             signalColor,
             true);

   DrawLabel(prefix + "TRADE",
             "Trade : " + tradeText,
             x,
             y + row++ * lh,
             fs,
             tradeColor,
             true);

   DrawLabel(prefix + "BALANCE",
             "Balance : " +
             DoubleToString(balance, 2),
             x,
             y + row++ * lh,
             fs,
             COL_WHITE);

   DrawLabel(prefix + "EQUITY",
             "Equity : " +
             DoubleToString(equity, 2),
             x,
             y + row++ * lh,
             fs,
             COL_WHITE);

   DrawLabel(prefix + "FLOAT",
             "Floating P/L : " +
             DoubleToString(floating, 2),
             x,
             y + row++ * lh,
             fs,
             floating >= 0 ?
             COL_BULL :
             COL_BEAR);

   DrawLabel(prefix + "TOTAL",
             "FVG B / Br / Inv : " +
             IntegerToString(g_totalBull) +
             " / " +
             IntegerToString(g_totalBear) +
             " / " +
             IntegerToString(g_totalInv),
             x,
             y + row++ * lh,
             fs,
             COL_GRAY);

   string mgmt = "Management : —";

   if(g_tradeActive)
   {
      if(g_tp2TrailDone)
         mgmt = "Management : SL → TP2";
      else
      if(g_tp1TrailDone)
         mgmt = "Management : SL → TP1";
      else
      if(g_beDone)
         mgmt = "Management : BE";
      else
         mgmt = "Management : INITIAL SL";
   }

   DrawLabel(prefix + "MGMT",
             mgmt,
             x,
             y + row++ * lh,
             fs,
             COL_CHROME,
             true);
}

//+------------------------------------------------------------------+
//| REMOVE DASHBOARD                                                 |
//+------------------------------------------------------------------+

void DeleteDashboard()
{
   string prefix = PREFIX + "DASH_";

   string names[] =
   {
      "TITLE",
      "BIAS",
      "BULL",
      "BEAR",
      "NEAR",
      "FILL",
      "GRADE",
      "FLIP",
      "SIGNAL",
      "TRADE",
      "BALANCE",
      "EQUITY",
      "FLOAT",
      "TOTAL",
      "MGMT"
   };

   for(int i = 0; i < ArraySize(names); i++)
      DeleteObjectSafe(prefix + names[i]);
}

//+------------------------------------------------------------------+
//| CALCULATE LOT                                                    |
//+------------------------------------------------------------------+

double CalculateLot(double entry,
                    double stop)
{
   if(!InpUseRiskPercent)
      return NormalizeVolume(InpFixedLot);

   double balance =
      AccountInfoDouble(ACCOUNT_BALANCE);

   double riskMoney =
      balance *
      InpRiskPercent /
      100.0;

   double tickSize =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_TRADE_TICK_SIZE);

   double tickValue =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_TRADE_TICK_VALUE);

   double distance =
      MathAbs(entry - stop);

   if(distance <= 0 ||
      tickSize <= 0 ||
      tickValue <= 0)
      return NormalizeVolume(InpFixedLot);

   double lossPerLot =
      (distance / tickSize) *
      tickValue;

   if(lossPerLot <= 0)
      return NormalizeVolume(InpFixedLot);

   double lots =
      riskMoney /
      lossPerLot;

   return NormalizeVolume(lots);
}

//+------------------------------------------------------------------+
//| NORMALIZE VOLUME                                                 |
//+------------------------------------------------------------------+

double NormalizeVolume(double lots)
{
   double minLot =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_VOLUME_MIN);

   double maxLot =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_VOLUME_MAX);

   double step =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_VOLUME_STEP);

   if(step <= 0)
      step = minLot;

   lots =
      MathMax(minLot,
              MathMin(maxLot,
                      lots));

   lots =
      MathFloor(lots / step) * step;

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| CHECK EXISTING POSITION                                          |
//+------------------------------------------------------------------+

bool HasOurPosition()
{
   for(int i = PositionsTotal() - 1;
       i >= 0;
       i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      long magic =
         PositionGetInteger(POSITION_MAGIC);

      if(symbol == _Symbol &&
         (ulong)magic == InpMagicNumber)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| FIND OUR POSITION                                                |
//+------------------------------------------------------------------+

bool GetOurPosition(ulong &ticket)
{
   for(int i = PositionsTotal() - 1;
       i >= 0;
       i--)
   {
      ulong t =
         PositionGetTicket(i);

      if(t == 0)
         continue;

      if(!PositionSelectByTicket(t))
         continue;

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      long magic =
         PositionGetInteger(POSITION_MAGIC);

      if(symbol == _Symbol &&
         (ulong)magic == InpMagicNumber)
      {
         ticket = t;
         return true;
      }
   }

   ticket = 0;

   return false;
}

//+------------------------------------------------------------------+
//| RESET TRADE STATE                                                |
//+------------------------------------------------------------------+

void ResetTradeState()
{
   g_tradeActive = false;
   g_tradeSide = 0;

   g_tradeOpenTime = 0;

   g_entry = 0;
   g_stop = 0;

   g_tp1 = 0;
   g_tp2 = 0;
   g_tp3 = 0;

   g_risk = 0;

   g_beDone = false;
   g_tp1TrailDone = false;
   g_tp2TrailDone = false;

   g_positionTicket = 0;

   DeleteActiveTradeObjects();
}

//+------------------------------------------------------------------+
//| LOAD TRADE STATE FROM POSITION                                   |
//+------------------------------------------------------------------+

bool LoadTradeFromPosition()
{
   ulong ticket;

   if(!GetOurPosition(ticket))
   {
      if(g_tradeActive)
         ResetTradeState();

      return false;
   }

   if(g_tradeActive)
   {
      g_positionTicket = ticket;
      return true;
   }

   if(!PositionSelectByTicket(ticket))
      return false;

   ENUM_POSITION_TYPE type =
      (ENUM_POSITION_TYPE)
      PositionGetInteger(POSITION_TYPE);

   g_tradeSide =
      type == POSITION_TYPE_BUY ?
      1 : -1;

   g_entry =
      PositionGetDouble(POSITION_PRICE_OPEN);

   g_stop =
      PositionGetDouble(POSITION_SL);

   g_positionTicket = ticket;

   // Recover R from the initial SL where possible.
   // If restarted after management, derive using TP3 relationship.
   double storedRisk =
      MathAbs(g_entry - g_stop);

   if(storedRisk <= 0)
      storedRisk = GetATR(1);

   g_risk = storedRisk;

   if(g_risk <= 0)
      g_risk = PointValue() * 100;

   if(g_tradeSide == 1)
   {
      g_tp1 =
         g_entry +
         g_risk * InpTP1R;

      g_tp2 =
         g_entry +
         g_risk * InpTP2R;

      g_tp3 =
         g_entry +
         g_risk * InpTP3R;
   }
   else
   {
      g_tp1 =
         g_entry -
         g_risk * InpTP1R;

      g_tp2 =
         g_entry -
         g_risk * InpTP2R;

      g_tp3 =
         g_entry -
         g_risk * InpTP3R;
   }

   g_tradeOpenTime =
      (datetime)
      PositionGetInteger(POSITION_TIME);

   g_tradeActive = true;

   DrawActiveTrade();

   return true;
}

//+------------------------------------------------------------------+
//| OPEN TRADE                                                       |
//+------------------------------------------------------------------+

bool OpenTrade(int direction,
               double grade,
               string signalTag)
{
   if(InpOneTradeOnly && HasOurPosition())
      return false;

   if(direction == 1 && !InpTradeLong)
      return false;

   if(direction == -1 && !InpTradeShort)
      return false;

   double atr = GetATR(1);

   if(atr <= 0)
      return false;

   double entry =
      direction == 1 ?
      SymbolInfoDouble(_Symbol,
                       SYMBOL_ASK) :
      SymbolInfoDouble(_Symbol,
                       SYMBOL_BID);

   double rawStop;

   if(InpStopMode == STOP_ATR)
   {
      rawStop =
         direction == 1 ?
         entry - atr * InpATRStopDistance :
         entry + atr * InpATRStopDistance;
   }
   else
   {
      rawStop =
         direction == 1 ?
         g_signalBottom -
         atr * InpGapStopBufferATR :
         g_signalTop +
         atr * InpGapStopBufferATR;
   }

   double risk0 =
      MathAbs(entry - rawStop);

   double minRisk =
      atr * InpMinRiskATR;

   double maxRisk =
      atr * InpMaxRiskATR;

   double risk =
      MathMin(MathMax(risk0,
                      minRisk),
              maxRisk);

   double stop =
      direction == 1 ?
      entry - risk :
      entry + risk;

   double tp1 =
      direction == 1 ?
      entry + risk * InpTP1R :
      entry - risk * InpTP1R;

   double tp2 =
      direction == 1 ?
      entry + risk * InpTP2R :
      entry - risk * InpTP2R;

   double tp3 =
      direction == 1 ?
      entry + risk * InpTP3R :
      entry - risk * InpTP3R;

   entry = NormalizePrice(entry);
   stop  = NormalizePrice(stop);
   tp1   = NormalizePrice(tp1);
   tp2   = NormalizePrice(tp2);
   tp3   = NormalizePrice(tp3);

   double lots =
      CalculateLot(entry,
                   stop);

   if(lots <= 0)
      return false;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpTradeDeviationPoints);

   bool result = false;

   if(direction == 1)
   {
      result =
         trade.Buy(lots,
                   _Symbol,
                   0.0,
                   stop,
                   tp3,
                   "FVG JOAT BUY");
   }
   else
   {
      result =
         trade.Sell(lots,
                    _Symbol,
                    0.0,
                    stop,
                    tp3,
                    "FVG JOAT SELL");
   }

   if(!result)
   {
      Print("OPEN FAILED: ",
            trade.ResultRetcode(),
            " ",
            trade.ResultRetcodeDescription());

      return false;
   }

   g_tradeActive = true;

   g_tradeSide = direction;

   g_entry = entry;

   g_stop = stop;

   g_tp1 = tp1;
   g_tp2 = tp2;
   g_tp3 = tp3;

   g_risk = risk;

   g_tradeOpenTime =
      TimeCurrent();

   g_beDone = false;
   g_tp1TrailDone = false;
   g_tp2TrailDone = false;

   g_signalGrade = grade;
   g_signalTag = signalTag;

   ulong ticket;

   if(GetOurPosition(ticket))
      g_positionTicket = ticket;

   DrawActiveTrade();

   Print("FVG JOAT TRADE OPENED: ",
         direction == 1 ? "BUY" : "SELL",
         " Entry=",
         DoubleToString(g_entry, _Digits),
         " SL=",
         DoubleToString(g_stop, _Digits),
         " TP1=",
         DoubleToString(g_tp1, _Digits),
         " TP2=",
         DoubleToString(g_tp2, _Digits),
         " TP3=",
         DoubleToString(g_tp3, _Digits));

   return true;
}

//+------------------------------------------------------------------+
//| MODIFY SL                                                        |
//+------------------------------------------------------------------+

bool ModifyPositionSL(double newSL)
{
   ulong ticket;

   if(!GetOurPosition(ticket))
      return false;

   if(!PositionSelectByTicket(ticket))
      return false;

   double currentTP =
      PositionGetDouble(POSITION_TP);

   newSL =
      NormalizePrice(newSL);

   if(!trade.PositionModify(ticket,
                            newSL,
                            currentTP))
   {
      Print("SL MODIFY FAILED: ",
            trade.ResultRetcode(),
            " ",
            trade.ResultRetcodeDescription());

      return false;
   }

   g_stop = newSL;

   return true;
}

//+------------------------------------------------------------------+
//| MANAGE TRADE                                                     |
//+------------------------------------------------------------------+

void ManageTrade()
{
   ulong ticket;

   if(!GetOurPosition(ticket))
   {
      if(g_tradeActive)
         ResetTradeState();

      return;
   }

   if(!g_tradeActive)
   {
      if(!LoadTradeFromPosition())
         return;
   }

   if(!PositionSelectByTicket(ticket))
      return;

   double bid =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_BID);

   double ask =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_ASK);

   double price =
      g_tradeSide == 1 ?
      bid :
      ask;

   if(g_risk <= 0)
      return;

   double rMove;

   if(g_tradeSide == 1)
      rMove =
         (price - g_entry) /
         g_risk;
   else
      rMove =
         (g_entry - price) /
         g_risk;

   //===============================================================
   // 1. BE AT +0.30R
   //===============================================================

   if(!g_beDone &&
      rMove >= InpBETriggerR)
   {
      double newSL =
         g_entry;

      bool valid =
         g_tradeSide == 1 ?
         newSL > g_stop :
         newSL < g_stop;

      if(valid)
      {
         if(ModifyPositionSL(newSL))
         {
            g_beDone = true;

            Print("FVG JOAT: BE activated at +",
                  DoubleToString(rMove, 2),
                  "R");
         }
      }
      else
      {
         g_beDone = true;
      }
   }

   //===============================================================
   // 2. SL -> TP1 AT +1.30R
   //===============================================================

   if(!g_tp1TrailDone &&
      rMove >= InpTP1TrailTriggerR)
   {
      double newSL =
         g_tp1;

      bool valid =
         g_tradeSide == 1 ?
         newSL > g_stop :
         newSL < g_stop;

      if(valid)
      {
         if(ModifyPositionSL(newSL))
         {
            g_tp1TrailDone = true;

            Print("FVG JOAT: SL moved to TP1 at +",
                  DoubleToString(rMove, 2),
                  "R");
         }
      }
      else
      {
         g_tp1TrailDone = true;
      }
   }

   //===============================================================
   // 3. SL -> TP2 AT +2.30R
   //===============================================================

   if(!g_tp2TrailDone &&
      rMove >= InpTP2TrailTriggerR)
   {
      double newSL =
         g_tp2;

      bool valid =
         g_tradeSide == 1 ?
         newSL > g_stop :
         newSL < g_stop;

      if(valid)
      {
         if(ModifyPositionSL(newSL))
         {
            g_tp2TrailDone = true;

            Print("FVG JOAT: SL moved to TP2 at +",
                  DoubleToString(rMove, 2),
                  "R");
         }
      }
      else
      {
         g_tp2TrailDone = true;
      }
   }

   //===============================================================
   // 4. MAX TRADE DURATION
   //===============================================================

   if(g_tradeOpenTime > 0)
   {
      int barsElapsed =
         iBarShift(_Symbol,
                   PERIOD_M5,
                   g_tradeOpenTime,
                   false);

      if(barsElapsed >= InpMaxTradeBars)
      {
         double closePrice = price;

         if(trade.PositionClose(ticket))
         {
            DrawExitLabel("EXIT TIME",
                          closePrice,
                          COL_CHROME);

            Print("FVG JOAT: Trade closed by max duration.");

            ResetTradeState();

            return;
         }
      }
   }

   //===============================================================
   // DRAWINGS EXTENSION
   //===============================================================

   ExtendActiveTradeDrawing();
}

//+------------------------------------------------------------------+
//| EXTEND ACTIVE TRADE DRAWING                                      |
//+------------------------------------------------------------------+

void ExtendActiveTradeDrawing()
{
   if(!g_tradeActive)
      return;

   datetime right =
      iTime(_Symbol,
            PERIOD_M5,
            0) +
      PeriodSeconds(PERIOD_M5) *
      InpProjectionBars;

   string lines[] =
   {
      g_entryLineName,
      g_slLineName,
      g_tp1LineName,
      g_tp2LineName,
      g_tp3LineName
   };

   for(int i = 0; i < ArraySize(lines); i++)
   {
      if(lines[i] == "")
         continue;

      if(ObjectFind(0, lines[i]) >= 0)
         ObjectMove(0,
                    lines[i],
                    1,
                    right,
                    ObjectGetDouble(0,
                                    lines[i],
                                    OBJPROP_PRICE, 0));
   }

   string labels[] =
   {
      g_entryLabelName,
      g_slLabelName,
      g_tp1LabelName,
      g_tp2LabelName,
      g_tp3LabelName
   };

   double prices[] =
   {
      g_entry,
      g_stop,
      g_tp1,
      g_tp2,
      g_tp3
   };

   for(int i = 0; i < ArraySize(labels); i++)
   {
      if(labels[i] == "")
         continue;

      if(ObjectFind(0, labels[i]) >= 0)
      {
         ObjectMove(0,
                    labels[i],
                    0,
                    right,
                    prices[i]);
      }
   }

   if(g_targetZoneName != "")
   {
      if(ObjectFind(0,
                    g_targetZoneName) >= 0)
      {
         double top =
            MathMax(g_entry,
                    g_tp3);

         double bot =
            MathMin(g_entry,
                    g_tp3);

         ObjectMove(0,
                    g_targetZoneName,
                    1,
                    right,
                    bot);

         ObjectMove(0,
                    g_targetZoneName,
                    0,
                    iTime(_Symbol,
                          PERIOD_M5,
                          0),
                    top);
      }
   }

   if(g_riskZoneName != "")
   {
      if(ObjectFind(0,
                    g_riskZoneName) >= 0)
      {
         double top =
            MathMax(g_entry,
                    g_stop);

         double bot =
            MathMin(g_entry,
                    g_stop);

         ObjectMove(0,
                    g_riskZoneName,
                    1,
                    right,
                    bot);

         ObjectMove(0,
                    g_riskZoneName,
                    0,
                    iTime(_Symbol,
                          PERIOD_M5,
                          0),
                    top);
      }
   }
}

//+------------------------------------------------------------------+
//| CLOSE POSITION ON TP3/SL                                         |
//+------------------------------------------------------------------+

void CheckFinalExit()
{
   ulong ticket;

   if(!GetOurPosition(ticket))
      return;

   if(!g_tradeActive)
      return;

   double bid =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_BID);

   double ask =
      SymbolInfoDouble(_Symbol,
                       SYMBOL_ASK);

   double price =
      g_tradeSide == 1 ?
      bid :
      ask;

   bool tp3Hit =
      g_tradeSide == 1 ?
      price >= g_tp3 :
      price <= g_tp3;

   if(tp3Hit)
   {
      if(trade.PositionClose(ticket))
      {
         DrawExitLabel(
            "TP3 ✔ +" +
            DoubleToString(InpTP3R, 1) +
            "R",
            g_tp3,
            COL_BULL);

         Print("FVG JOAT: TP3 reached.");

         ResetTradeState();
      }
   }
}

//+------------------------------------------------------------------+
//| PROCESS CLOSED M5 BAR                                            |
//+------------------------------------------------------------------+

void ProcessNewM5Bar()
{
   g_buySignal = false;
   g_sellSignal = false;

   g_signalTag = "";

   g_signalTop = 0;
   g_signalBottom = 0;
   g_signalGrade = 0;

   MqlRates rates[];

   ArraySetAsSeries(rates, true);

   if(CopyRates(_Symbol,
                PERIOD_M5,
                0,
                5,
                rates) < 5)
      return;

   //===============================================================
   // CLOSED BAR = rates[1]
   // Equivalent to Pine's confirmed current bar.
   //===============================================================

   double atr = GetATR(1);

   if(atr <= 0)
      return;

   int htfBias =
      GetHTFBias();

   bool useRejection =
      InpSignalMode ==
      SIGNAL_REJECTION_ONLY ||
      InpSignalMode ==
      SIGNAL_REJECTION_IFVG;

   bool useIFVG =
      InpSignalMode ==
      SIGNAL_IFVG_ONLY ||
      InpSignalMode ==
      SIGNAL_REJECTION_IFVG;

   //===============================================================
   // 1. UPDATE EXISTING GAPS
   //===============================================================

   for(int i = ArraySize(Gaps) - 1;
       i >= 0;
       i--)
   {
      FVGGap &f =
         Gaps[i];

      int age =
         iBarShift(_Symbol,
                   PERIOD_M5,
                   f.bornTime,
                   false);

      if(age < 0)
         age = 0;

      bool remove = false;

      if(!f.inverted)
      {
         //-----------------------------------------------------------
         // BULLISH GAP
         //-----------------------------------------------------------
         if(f.direction == 1)
         {
            f.extreme =
               MathMin(f.extreme,
                       rates[1].low);

            double range =
               MathMax(f.top -
                       f.bottom,
                       _Point);

            f.fillPct =
               MathMax(
                  0.0,
                  MathMin(
                     1.0,
                     (f.top -
                      f.extreme) /
                     range));

            // Full wick mitigation
            if(rates[1].low <= f.bottom)
            {
               f.mitigated = true;

               if(InpShowGapBoxes)
               {
                  if(f.boxName != "")
                  {
                     DeleteObjectSafe(f.boxName);
                     f.boxName = "";
                  }

                  if(f.midName != "")
                  {
                     DeleteObjectSafe(f.midName);
                     f.midName = "";
                  }
               }
            }

            // IFVG inversion
            if(rates[1].close < f.bottom)
            {
               f.inverted = true;

               g_totalInv++;

               g_lastFlipDir = -1;
               g_lastFlipTime =
                  rates[1].time;

               RestyleIFVG(f);

               if(useIFVG &&
                  InpAllowBearFVG &&
                  htfBias <= 0 &&
                  f.grade >= InpMinSignalGrade)
               {
                  g_sellSignal = true;

                  g_signalTag = "IFVG▼";

                  g_signalTop = f.top;
                  g_signalBottom = f.bottom;
                  g_signalGrade = f.grade;
               }
            }
         }

         //-----------------------------------------------------------
         // BEARISH GAP
         //-----------------------------------------------------------
         else
         {
            f.extreme =
               MathMax(f.extreme,
                       rates[1].high);

            double range =
               MathMax(f.top -
                       f.bottom,
                       _Point);

            f.fillPct =
               MathMax(
                  0.0,
                  MathMin(
                     1.0,
                     (f.extreme -
                      f.bottom) /
                     range));

            // Full wick mitigation
            if(rates[1].high >= f.top)
            {
               f.mitigated = true;

               if(InpShowGapBoxes)
               {
                  if(f.boxName != "")
                  {
                     DeleteObjectSafe(f.boxName);
                     f.boxName = "";
                  }

                  if(f.midName != "")
                  {
                     DeleteObjectSafe(f.midName);
                     f.midName = "";
                  }
               }
            }

            // IFVG inversion
            if(rates[1].close > f.top)
            {
               f.inverted = true;

               g_totalInv++;

               g_lastFlipDir = 1;
               g_lastFlipTime =
                  rates[1].time;

               RestyleIFVG(f);

               if(useIFVG &&
                  InpAllowBullFVG &&
                  htfBias >= 0 &&
                  f.grade >= InpMinSignalGrade)
               {
                  g_buySignal = true;

                  g_signalTag = "IFVG▲";

                  g_signalTop = f.top;
                  g_signalBottom = f.bottom;
                  g_signalGrade = f.grade;
               }
            }
         }
      }

      //=============================================================
      // REJECTION
      //=============================================================

      if(useRejection &&
         !f.mitigated &&
         !f.inverted &&
         !f.reacted &&
         age >= 1)
      {
         //-----------------------------------------------------------
         // BULLISH REJECTION
         //-----------------------------------------------------------
         if(f.direction == 1 &&
            InpAllowBullFVG)
         {
            bool tapped =
               rates[1].low <= f.top &&
               rates[1].low >= f.bottom &&
               rates[1].close > f.bottom;

            bool directionalClose =
               !InpRequireDirectionalClose ||
               rates[1].close >
               rates[1].open;

            if(tapped &&
               directionalClose &&
               f.grade >= InpMinSignalGrade &&
               htfBias >= 0)
            {
               f.reacted = true;

               g_buySignal = true;

               g_signalTag = "FVG▲";

               g_signalTop = f.top;
               g_signalBottom = f.bottom;
               g_signalGrade = f.grade;
            }
         }

         //-----------------------------------------------------------
         // BEARISH REJECTION
         //-----------------------------------------------------------
         if(f.direction == -1 &&
            InpAllowBearFVG)
         {
            bool tapped =
               rates[1].high >= f.bottom &&
               rates[1].high <= f.top &&
               rates[1].close < f.top;

            bool directionalClose =
               !InpRequireDirectionalClose ||
               rates[1].close <
               rates[1].open;

            if(tapped &&
               directionalClose &&
               f.grade >= InpMinSignalGrade &&
               htfBias <= 0)
            {
               f.reacted = true;

               g_sellSignal = true;

               g_signalTag = "FVG▼";

               g_signalTop = f.top;
               g_signalBottom = f.bottom;
               g_signalGrade = f.grade;
            }
         }
      }

      //=============================================================
      // AGE OUT
      //=============================================================

      if(age > InpGapLifetimeBars)
         remove = true;

      if(remove)
      {
         DeleteFVGObjects(f);

         ArrayRemove(Gaps,
                     i,
                     1);
      }
      else
      {
         UpdateFVGDrawing(f);
      }
   }

   //===============================================================
   // 2. NEW FVG DETECTION
   //
   // Pine:
   // bullish = low > high[2]
   // bearish = high < low[2]
   //
   // For confirmed M5 bar rates[1]:
   // bullish = low[1] > high[3]
   // bearish = high[1] < low[3]
   //===============================================================

   double middleRange =
      rates[2].high -
      rates[2].low;

   if(middleRange <= 0)
      middleRange = _Point;

   double bodyRatio =
      MathAbs(
         rates[2].close -
         rates[2].open) /
      middleRange;

   double disp3 =
      middleRange /
      atr;

   double volAvg = 0.0;

   MqlRates volumeRates[];

   ArraySetAsSeries(volumeRates,
                    true);

   int copied =
      CopyRates(_Symbol,
                PERIOD_M5,
                2,
                20,
                volumeRates);

   if(copied > 0)
   {
      double totalVol = 0;

      for(int i = 0;
          i < copied;
          i++)
      {
         totalVol +=
            (double)
            volumeRates[i].tick_volume;
      }

      volAvg =
         totalVol /
         copied;
   }

   double currentVol =
      (double)
      rates[2].tick_volume;

   double volScore = 0.5;

   if(volAvg > 0)
   {
      volScore =
         MathMin(currentVol /
                 volAvg,
                 2.0) /
         2.0;
   }

   //---------------------------------------------------------------
   // NEW BULLISH FVG
   //---------------------------------------------------------------

   bool newBull =
      InpAllowBullFVG &&
      rates[1].low >
      rates[3].high;

   if(newBull)
   {
      double top =
         rates[1].low;

      double bottom =
         rates[3].high;

      double gapATR =
         (top - bottom) /
         atr;

      if(gapATR >= InpMinGapATR &&
         bodyRatio >= InpMinBodyRatio)
      {
         double sizeScore =
            MathMin(gapATR / 1.0,
                    1.0);

         double dispScore =
            MathMin(disp3 / 2.0,
                    1.0);

         double grade =
            MathMin(
               10.0,
               (sizeScore * 0.40 +
                dispScore * 0.35 +
                volScore * 0.25) *
               10.0);

         FVGGap f;

         f.top = top;
         f.bottom = bottom;

         f.direction = 1;

         f.bornTime =
            rates[1].time;

         f.bornBar =
            iBarShift(_Symbol,
                      PERIOD_M5,
                      rates[1].time,
                      false);

         f.grade = grade;

         f.extreme = top;

         f.fillPct = 0.0;

         f.mitigated = false;
         f.inverted = false;
         f.reacted = false;

         f.boxName = "";
         f.midName = "";

         DrawFVG(f);

         int newSize =
            ArraySize(Gaps) + 1;

         ArrayResize(Gaps,
                     newSize);

         Gaps[newSize - 1] = f;

         g_totalBull++;
      }
   }

   //---------------------------------------------------------------
   // NEW BEARISH FVG
   //---------------------------------------------------------------

   bool newBear =
      InpAllowBearFVG &&
      rates[1].high <
      rates[3].low;

   if(newBear)
   {
      double top =
         rates[3].low;

      double bottom =
         rates[1].high;

      double gapATR =
         (top - bottom) /
         atr;

      if(gapATR >= InpMinGapATR &&
         bodyRatio >= InpMinBodyRatio)
      {
         double sizeScore =
            MathMin(gapATR / 1.0,
                    1.0);

         double dispScore =
            MathMin(disp3 / 2.0,
                    1.0);

         double grade =
            MathMin(
               10.0,
               (sizeScore * 0.40 +
                dispScore * 0.35 +
                volScore * 0.25) *
               10.0);

         FVGGap f;

         f.top = top;
         f.bottom = bottom;

         f.direction = -1;

         f.bornTime =
            rates[1].time;

         f.bornBar =
            iBarShift(_Symbol,
                      PERIOD_M5,
                      rates[1].time,
                      false);

         f.grade = grade;

         f.extreme = bottom;

         f.fillPct = 0.0;

         f.mitigated = false;
         f.inverted = false;
         f.reacted = false;

         f.boxName = "";
         f.midName = "";

         DrawFVG(f);

         int newSize =
            ArraySize(Gaps) + 1;

         ArrayResize(Gaps,
                     newSize);

         Gaps[newSize - 1] = f;

         g_totalBear++;
      }
   }

   //===============================================================
   // 3. GAP CAP
   //===============================================================

   while(ArraySize(Gaps) >
         InpMaxVisibleGaps)
   {
      DeleteFVGObjects(Gaps[0]);

      ArrayRemove(Gaps,
                  0,
                  1);
   }

   //===============================================================
   // 4. SIGNAL -> TRADE
   //===============================================================

   bool takeLong =
      g_buySignal &&
      !g_tradeActive &&
      !HasOurPosition() &&
      g_signalBottom > 0;

   bool takeShort =
      g_sellSignal &&
      !g_tradeActive &&
      !HasOurPosition() &&
      g_signalTop > 0 &&
      !takeLong;

   if(takeLong)
   {
      DrawSignal(1,
                 g_signalGrade,
                 g_signalTag);

      OpenTrade(1,
                g_signalGrade,
                g_signalTag);
   }
   else
   if(takeShort)
   {
      DrawSignal(-1,
                 g_signalGrade,
                 g_signalTag);

      OpenTrade(-1,
                g_signalGrade,
                g_signalTag);
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| DELETE ALL EA OBJECTS                                            |
//+------------------------------------------------------------------+

void DeleteAllEAObjects()
{
   int total =
      ObjectsTotal(0);

   for(int i = total - 1;
       i >= 0;
       i--)
   {
      string name =
         ObjectName(0, i);

      if(StringFind(name,
                    PREFIX) == 0)
      {
         ObjectDelete(0,
                      name);
      }
   }
}

//+------------------------------------------------------------------+
//| INITIALIZATION                                                   |
//+------------------------------------------------------------------+

int OnInit()
{
   if(InpRequireM5Chart &&
      Period() != PERIOD_M5)
   {
      Print("FVG JOAT: Attach this EA to M5.");

      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(
      InpMagicNumber);

   trade.SetDeviationInPoints(
      InpTradeDeviationPoints);

   //===============================================================
   // ATR
   //===============================================================

   g_atrHandle =
      iATR(_Symbol,
           PERIOD_M5,
           InpATRLength);

   if(g_atrHandle ==
      INVALID_HANDLE)
   {
      Print("Failed to create ATR handle.");

      return INIT_FAILED;
   }

   //===============================================================
   // HTF EMA
   //===============================================================

   g_emaHandle =
      iMA(_Symbol,
          InpHTF,
          InpHTFEMALength,
          0,
          MODE_EMA,
          PRICE_CLOSE);

   if(g_emaHandle ==
      INVALID_HANDLE)
   {
      Print("Failed to create HTF EMA handle.");

      return INIT_FAILED;
   }

   //===============================================================
   // INITIAL BAR
   //===============================================================

   g_lastM5Bar =
      iTime(_Symbol,
            PERIOD_M5,
            0);

   //===============================================================
   // RECOVER POSITION
   //===============================================================

   if(HasOurPosition())
      LoadTradeFromPosition();

   UpdateDashboard();

   Print("==================================================");
   Print("FVG SNIPER [JOAT] EA INITIALIZED");
   Print("Symbol       : ", _Symbol);
   Print("HTF          : H1");
   Print("LTF          : M5");
   Print("Magic        : ", InpMagicNumber);
   Print("BE           : +",
         DoubleToString(InpBETriggerR, 2),
         "R");
   Print("Trail TP1    : +",
         DoubleToString(InpTP1TrailTriggerR, 2),
         "R -> SL TP1");
   Print("Trail TP2    : +",
         DoubleToString(InpTP2TrailTriggerR, 2),
         "R -> SL TP2");
   Print("TP3          : ",
         DoubleToString(InpTP3R, 2),
         "R");
   Print("==================================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINITIALIZATION                                                 |
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
{
   if(g_atrHandle !=
      INVALID_HANDLE)
   {
      IndicatorRelease(
         g_atrHandle);

      g_atrHandle =
         INVALID_HANDLE;
   }

   if(g_emaHandle !=
      INVALID_HANDLE)
   {
      IndicatorRelease(
         g_emaHandle);

      g_emaHandle =
         INVALID_HANDLE;
   }

   DeleteAllEAObjects();

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| TICK                                                             |
//+------------------------------------------------------------------+

void OnTick()
{
   //===============================================================
   // FIRST: ALWAYS MANAGE EXISTING TRADE
   //===============================================================

   ManageTrade();

   CheckFinalExit();

   //===============================================================
   // NEW M5 BAR DETECTION
   //===============================================================

   datetime currentBar =
      iTime(_Symbol,
            PERIOD_M5,
            0);

   if(currentBar <= 0)
      return;

   if(currentBar !=
      g_lastM5Bar)
   {
      g_lastM5Bar =
         currentBar;

      ProcessNewM5Bar();
   }

   //===============================================================
   // DASHBOARD
   //===============================================================

   UpdateDashboard();

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTION                                                |
//+------------------------------------------------------------------+

void OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result)
{
   //===============================================================
   // POSITION CLOSED
   //===============================================================

   if(trans.type ==
      TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong deal =
         trans.deal;

      if(deal == 0)
         return;

      if(!HistoryDealSelect(deal))
         return;

      string symbol =
         HistoryDealGetString(
            deal,
            DEAL_SYMBOL);

      long magic =
         HistoryDealGetInteger(
            deal,
            DEAL_MAGIC);

      if(symbol != _Symbol ||
         (ulong)magic != InpMagicNumber)
         return;

      long entryType =
         HistoryDealGetInteger(
            deal,
            DEAL_ENTRY);

      if(entryType ==
         DEAL_ENTRY_OUT)
      {
         double profit =
            HistoryDealGetDouble(
               deal,
               DEAL_PROFIT);

         double price =
            HistoryDealGetDouble(
               deal,
               DEAL_PRICE);

         if(profit >= 0)
         {
            DrawExitLabel(
               "TP ✔ " +
               DoubleToString(profit, 2),
               price,
               COL_BULL);
         }
         else
         {
            DrawExitLabel(
               "SL ✘ " +
               DoubleToString(profit, 2),
               price,
               COL_BEAR);
         }

         ResetTradeState();
      }
   }
}

//+------------------------------------------------------------------+
//| END                                                              |
//+------------------------------------------------------------------+
