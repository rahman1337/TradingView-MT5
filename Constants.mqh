//+------------------------------------------------------------------+
//| FVG_Sniper_Constants.mqh                                        |
//|                                                                  |
//| FVG SNIPER [JOAT] - MT5                                         |
//| Constants + Inputs                                               |
//|                                                                  |
//| LTF = M5                                                         |
//| HTF = H1                                                         |
//|                                                                  |
//| Signal logic is ported from the supplied Pine Script.            |
//| Trade management additions:                                     |
//|   +0.30R -> BE                                                   |
//|   +1.30R -> SL = TP1                                             |
//|   +2.30R -> SL = TP2                                             |
//+------------------------------------------------------------------+
#ifndef __FVG_SNIPER_CONSTANTS_MQH__
#define __FVG_SNIPER_CONSTANTS_MQH__

//+------------------------------------------------------------------+
//| Timeframes                                                       |
//+------------------------------------------------------------------+

#define FVG_LTF              PERIOD_M5
#define FVG_HTF              PERIOD_H1

//+------------------------------------------------------------------+
//| Magic Number                                                     |
//+------------------------------------------------------------------+

#define FVG_MAGIC_NUMBER     26081101

//+------------------------------------------------------------------+
//| Object Prefix                                                    |
//+------------------------------------------------------------------+

#define FVG_OBJECT_PREFIX    "FVGJOAT_"

//+------------------------------------------------------------------+
//| Engine Defaults                                                  |
//+------------------------------------------------------------------+

#define FVG_DEFAULT_ALLOW_BULL       true
#define FVG_DEFAULT_ALLOW_BEAR       true

#define FVG_DEFAULT_MAX_GAPS         14
#define FVG_DEFAULT_MAX_AGE          220
#define FVG_DEFAULT_EXTEND_BARS      12

//+------------------------------------------------------------------+
//| ATR / Grade Defaults                                             |
//+------------------------------------------------------------------+

#define FVG_DEFAULT_ATR_LENGTH       14
#define FVG_DEFAULT_MIN_GAP_ATR      0.25
#define FVG_DEFAULT_MIN_BODY_RATIO   0.45
#define FVG_DEFAULT_MIN_GRADE        4.0

//+------------------------------------------------------------------+
//| HTF Bias                                                         |
//+------------------------------------------------------------------+

#define FVG_DEFAULT_HTF_EMA          50

//+------------------------------------------------------------------+
//| Stop Defaults                                                    |
//+------------------------------------------------------------------+

#define FVG_DEFAULT_SL_BUFFER_ATR    0.20
#define FVG_DEFAULT_SL_ATR_MULT      1.50

#define FVG_DEFAULT_MIN_RISK_ATR     0.40
#define FVG_DEFAULT_MAX_RISK_ATR     4.00

//+------------------------------------------------------------------+
//| Take Profit Defaults                                             |
//+------------------------------------------------------------------+

#define FVG_DEFAULT_TP1_R            1.0
#define FVG_DEFAULT_TP2_R            2.0
#define FVG_DEFAULT_TP3_R            3.0

//+------------------------------------------------------------------+
//| Trade Management                                                 |
//+------------------------------------------------------------------+

#define FVG_DEFAULT_BE_R             0.30
#define FVG_DEFAULT_TRAIL1_R         1.30
#define FVG_DEFAULT_TRAIL2_R         2.30

#define FVG_DEFAULT_MAX_TRADE_BARS   120

//+------------------------------------------------------------------+
//| Chart Drawing                                                    |
//+------------------------------------------------------------------+

#define FVG_DEFAULT_PROJECTION_BARS  8
#define FVG_DEFAULT_MAX_HISTORY      20

#define FVG_DEFAULT_OB_BARS          12
#define FVG_DEFAULT_LINE_WIDTH       1

//+------------------------------------------------------------------+
//| Colors                                                           |
//+------------------------------------------------------------------+

#define FVG_COLOR_BULL               C'38,166,154'
#define FVG_COLOR_BEAR               C'239,83,80'
#define FVG_COLOR_IFVG               C'255,179,0'
#define FVG_COLOR_CHROME             C'198,214,224'
#define FVG_COLOR_RISK               C'230,45,60'

#define FVG_COLOR_DASH_BG            C'16,18,24'
#define FVG_COLOR_DASH_ALT           C'26,29,37'
#define FVG_COLOR_DASH_TEXT          C'232,236,242'
#define FVG_COLOR_DASH_MUTED         C'150,156,168'

//+------------------------------------------------------------------+
//| Signal Source                                                    |
//+------------------------------------------------------------------+

enum ENUM_FVG_SIGNAL_MODE
  {
   FVG_SIGNAL_REJECTION_ONLY = 0,
   FVG_SIGNAL_IFVG_ONLY      = 1,
   FVG_SIGNAL_REJECTION_IFVG = 2
  };

//+------------------------------------------------------------------+
//| Stop Basis                                                       |
//+------------------------------------------------------------------+

enum ENUM_FVG_STOP_MODE
  {
   FVG_STOP_GAP_PROTECTED = 0,
   FVG_STOP_ATR           = 1
  };

//+------------------------------------------------------------------+
//| Direction                                                        |
//+------------------------------------------------------------------+

enum ENUM_FVG_DIRECTION
  {
   FVG_DIRECTION_NONE = 0,
   FVG_DIRECTION_BULL = 1,
   FVG_DIRECTION_BEAR = -1
  };

//+------------------------------------------------------------------+
//| EA Inputs                                                        |
//+------------------------------------------------------------------+

input group "=== FVG SNIPER — ENGINE ==="

input bool InpAllowBullFVG =
   FVG_DEFAULT_ALLOW_BULL;

input bool InpAllowBearFVG =
   FVG_DEFAULT_ALLOW_BEAR;

input ENUM_FVG_SIGNAL_MODE InpSignalMode =
   FVG_SIGNAL_REJECTION_IFVG;

input int InpMaxVisibleGaps =
   FVG_DEFAULT_MAX_GAPS;

input int InpGapLifetimeBars =
   FVG_DEFAULT_MAX_AGE;

input int InpGapExtensionBars =
   FVG_DEFAULT_EXTEND_BARS;


input group "=== FVG SNIPER — FILTERS ==="

input int InpATRLength =
   FVG_DEFAULT_ATR_LENGTH;

input double InpMinGapATR =
   FVG_DEFAULT_MIN_GAP_ATR;

input double InpMinDisplacementBodyRatio =
   FVG_DEFAULT_MIN_BODY_RATIO;

input double InpMinSignalGrade =
   FVG_DEFAULT_MIN_GRADE;


input group "=== FVG SNIPER — HTF BIAS ==="

input bool InpUseHTFBias =
   true;

// Explicitly H1 as requested.
input ENUM_TIMEFRAMES InpHTF =
   FVG_HTF;

input int InpHTFEMALength =
   FVG_DEFAULT_HTF_EMA;

input bool InpRequireDirectionalClose =
   true;


input group "=== FVG SNIPER — TRADE MODEL ==="

input ENUM_FVG_STOP_MODE InpStopMode =
   FVG_STOP_GAP_PROTECTED;

input double InpGapStopBufferATR =
   FVG_DEFAULT_SL_BUFFER_ATR;

input double InpATRStopMultiplier =
   FVG_DEFAULT_SL_ATR_MULT;

input double InpMinimumRiskATR =
   FVG_DEFAULT_MIN_RISK_ATR;

input double InpMaximumRiskATR =
   FVG_DEFAULT_MAX_RISK_ATR;

input double InpTP1R =
   FVG_DEFAULT_TP1_R;

input double InpTP2R =
   FVG_DEFAULT_TP2_R;

input double InpTP3R =
   FVG_DEFAULT_TP3_R;


input group "=== FVG SNIPER — TRADE MANAGEMENT ==="

// User requested:
// +0.30R -> BE
input double InpBreakEvenR =
   FVG_DEFAULT_BE_R;

// User requested:
// +1.30R -> SL = TP1
input double InpTrailToTP1R =
   FVG_DEFAULT_TRAIL1_R;

// User requested:
// +2.30R -> SL = TP2
input double InpTrailToTP2R =
   FVG_DEFAULT_TRAIL2_R;

input int InpMaximumTradeBars =
   FVG_DEFAULT_MAX_TRADE_BARS;


input group "=== FVG SNIPER — EXECUTION ==="

input double InpLotSize =
   0.10;

input bool InpUseRiskPercent =
   false;

input double InpRiskPercent =
   1.0;

input int InpDeviationPoints =
   20;

input bool InpOneTradeOnly =
   true;

input ulong InpMagicNumber =
   FVG_MAGIC_NUMBER;


input group "=== FVG SNIPER — FVG DRAWING ==="

input bool InpShowFVGBoxes =
   true;

input bool InpShowFVGMidline =
   false;

input bool InpHideFilledFVG =
   false;

input bool InpShowIFVG =
   true;

input bool InpShowGrade =
   true;

input bool InpShowSignal =
   true;


input group "=== FVG SNIPER — TRADE DRAWING ==="

input bool InpShowTradeZones =
   true;

input bool InpShowTradeLines =
   true;

input bool InpShowLevelLabels =
   true;

input bool InpShowExitLabels =
   true;

input int InpProjectionBars =
   FVG_DEFAULT_PROJECTION_BARS;

input int InpMaxDrawnTrades =
   FVG_DEFAULT_MAX_HISTORY;

input int InpDrawingLineWidth =
   FVG_DEFAULT_LINE_WIDTH;


input group "=== FVG SNIPER — DASHBOARD ==="

input bool InpShowDashboard =
   true;

input int InpDashboardX =
   20;

input int InpDashboardY =
   30;

input int InpDashboardTextSize =
   9;

input int InpDashboardLineHeight =
   16;

input bool InpDashboardDarkPanel =
   true;

// Dashboard uses individual DrawLabel() objects.
input bool InpDashboardShowBalance =
   true;

input bool InpDashboardShowEquity =
   true;


input group "=== FVG SNIPER — GENERAL ==="

input bool InpEnableTrading =
   true;

input bool InpDrawOnChart =
   true;

input bool InpDeleteObjectsOnRemove =
   false;

//+------------------------------------------------------------------+
//| Object names                                                     |
//+------------------------------------------------------------------+

#define OBJ_FVG_BULL             FVG_OBJECT_PREFIX "FVG_BULL_"
#define OBJ_FVG_BEAR             FVG_OBJECT_PREFIX "FVG_BEAR_"
#define OBJ_FVG_MID              FVG_OBJECT_PREFIX "FVG_MID_"
#define OBJ_FVG_LABEL             FVG_OBJECT_PREFIX "FVG_LABEL_"

#define OBJ_IFVG                 FVG_OBJECT_PREFIX "IFVG_"
#define OBJ_SIGNAL               FVG_OBJECT_PREFIX "SIGNAL_"
#define OBJ_GRADE                FVG_OBJECT_PREFIX "GRADE_"

#define OBJ_ENTRY                FVG_OBJECT_PREFIX "ENTRY"
#define OBJ_SL                   FVG_OBJECT_PREFIX "SL"
#define OBJ_TP1                  FVG_OBJECT_PREFIX "TP1"
#define OBJ_TP2                  FVG_OBJECT_PREFIX "TP2"
#define OBJ_TP3                  FVG_OBJECT_PREFIX "TP3"

#define OBJ_TRADE_TARGET_ZONE    FVG_OBJECT_PREFIX "TARGET_ZONE"
#define OBJ_TRADE_RISK_ZONE      FVG_OBJECT_PREFIX "RISK_ZONE"

#define OBJ_EXIT                 FVG_OBJECT_PREFIX "EXIT_"

//+------------------------------------------------------------------+
//| Dashboard object names                                           |
//+------------------------------------------------------------------+

#define DASH_PREFIX              FVG_OBJECT_PREFIX "DASH_"

#define DASH_BG                  DASH_PREFIX "BG"
#define DASH_TITLE               DASH_PREFIX "TITLE"

#define DASH_HTF                 DASH_PREFIX "HTF"
#define DASH_BULL                DASH_PREFIX "BULL"
#define DASH_BEAR                DASH_PREFIX "BEAR"
#define DASH_NEAREST             DASH_PREFIX "NEAREST"
#define DASH_FILL                DASH_PREFIX "FILL"
#define DASH_GRADE               DASH_PREFIX "GRADE"
#define DASH_IFVG                DASH_PREFIX "IFVG"
#define DASH_SIGNAL              DASH_PREFIX "SIGNAL"
#define DASH_TRADE               DASH_PREFIX "TRADE"
#define DASH_BALANCE             DASH_PREFIX "BALANCE"
#define DASH_EQUITY              DASH_PREFIX "EQUITY"
#define DASH_STATUS              DASH_PREFIX "STATUS"

//+------------------------------------------------------------------+
//| Utility constants                                                |
//+------------------------------------------------------------------+

#define FVG_EPSILON              0.0000000001

//+------------------------------------------------------------------+
//| Helper: direction text                                           |
//+------------------------------------------------------------------+

string FVGDirectionText(const int direction)
  {
   if(direction == FVG_DIRECTION_BULL)
      return "BULLISH";

   if(direction == FVG_DIRECTION_BEAR)
      return "BEARISH";

   return "NEUTRAL";
  }

//+------------------------------------------------------------------+
//| Helper: signal direction text                                    |
//+------------------------------------------------------------------+

string FVGSignalText(const int direction)
  {
   if(direction == FVG_DIRECTION_BULL)
      return "BUY";

   if(direction == FVG_DIRECTION_BEAR)
      return "SELL";

   return "—";
  }

//+------------------------------------------------------------------+
//| Helper: signal tag                                               |
//+------------------------------------------------------------------+

string FVGSignalTag(const int direction,
                    const bool isIFVG)
  {
   if(direction == FVG_DIRECTION_BULL)
     {
      if(isIFVG)
         return "IFVG▲";

      return "FVG▲";
     }

   if(direction == FVG_DIRECTION_BEAR)
     {
      if(isIFVG)
         return "IFVG▼";

      return "FVG▼";
     }

   return "—";
  }

//+------------------------------------------------------------------+
//| Helper: stars                                                    |
//+------------------------------------------------------------------+

string FVGGradeStars(const double grade)
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
//| Helper: signed R                                                 |
//+------------------------------------------------------------------+

string FVGSignedR(const double value)
  {
   if(value >= 0.0)
      return "+" + DoubleToString(value, 2) + "R";

   return DoubleToString(value, 2) + "R";
  }

//+------------------------------------------------------------------+
//| Helper: normalize price                                         |
//+------------------------------------------------------------------+

double FVGNormalizePrice(const string symbol,
                         const double price)
  {
   int digits =
      (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   return NormalizeDouble(price, digits);
  }

//+------------------------------------------------------------------+
//| Helper: minimum tick                                             |
//+------------------------------------------------------------------+

double FVGMinTick(const string symbol)
  {
   double tick = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tick <= 0.0)
      tick = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(tick <= 0.0)
      tick = 0.00001;

   return tick;
  }

//+------------------------------------------------------------------+
//| Helper: normalize volume                                         |
//+------------------------------------------------------------------+

double FVGNormalizeVolume(const string symbol,
                          const double volume)
  {
   double minLot =
      SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

   double maxLot =
      SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   double step =
      SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0)
      step = minLot;

   if(step <= 0.0)
      step = 0.01;

   double v = MathMax(volume, minLot);
   v = MathMin(v, maxLot);

   v = MathFloor(v / step) * step;

   int volDigits = 2;

   if(step >= 1.0)
      volDigits = 0;
   else if(step >= 0.1)
      volDigits = 1;
   else if(step >= 0.01)
      volDigits = 2;
   else if(step >= 0.001)
      volDigits = 3;

   return NormalizeDouble(v, volDigits);
  }

//+------------------------------------------------------------------+
//| Helper: timeframe name                                           |
//+------------------------------------------------------------------+

string FVGTimeframeText(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:
         return "M1";

      case PERIOD_M5:
         return "M5";

      case PERIOD_M15:
         return "M15";

      case PERIOD_M30:
         return "M30";

      case PERIOD_H1:
         return "H1";

      case PERIOD_H4:
         return "H4";

      case PERIOD_D1:
         return "D1";

      case PERIOD_W1:
         return "W1";

      case PERIOD_MN1:
         return "MN1";
     }

   return "TF";
  }

//+------------------------------------------------------------------+
//| Helper: safe division                                            |
//+------------------------------------------------------------------+

double FVGSafeDivide(const double numerator,
                     const double denominator,
                     const double fallback = 0.0)
  {
   if(MathAbs(denominator) <= FVG_EPSILON)
      return fallback;

   return numerator / denominator;
  }

//+------------------------------------------------------------------+
//| Helper: clamp                                                    |
//+------------------------------------------------------------------+

double FVGClamp(const double value,
                const double minimum,
                const double maximum)
  {
   return MathMax(minimum,
                  MathMin(maximum, value));
  }

//+------------------------------------------------------------------+
//| Helper: R distance                                               |
//+------------------------------------------------------------------+

double FVGRPrice(const int direction,
                 const double entry,
                 const double risk,
                 const double r)
  {
   if(direction == FVG_DIRECTION_BULL)
      return entry + risk * r;

   if(direction == FVG_DIRECTION_BEAR)
      return entry - risk * r;

   return entry;
  }

//+------------------------------------------------------------------+
//| End                                                              |
//+------------------------------------------------------------------+
#endif
