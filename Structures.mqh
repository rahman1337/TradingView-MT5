//+------------------------------------------------------------------+
//| FVG_Sniper_Structures.mqh                                       |
//|                                                                  |
//| FVG SNIPER [JOAT]                                                |
//| Data structures / engine state                                  |
//|                                                                  |
//| LTF = M5                                                         |
//| HTF = H1                                                         |
//+------------------------------------------------------------------+
#ifndef __FVG_SNIPER_STRUCTURES_MQH__
#define __FVG_SNIPER_STRUCTURES_MQH__

#include "Constants.mqh"

//+------------------------------------------------------------------+
//| FVG lifecycle state                                              |
//+------------------------------------------------------------------+
//
// Original Pine states:
//
//   mitigated = wick fully traversed the gap
//   inverted  = candle closed completely through the gap
//   reacted   = rejection signal already fired
//
// These states belong to EACH individual FVG.
//+------------------------------------------------------------------+

struct FVGGap
  {
   //--- Identification
   long               id;

   //--- Direction
   int                direction;

   //--- Price boundaries
   double             top;
   double             bottom;

   //--- Creation
   datetime           createdTime;
   int                bornBar;

   //--- Quality
   double             grade;

   //--- Running extreme inside gap
   double             extreme;

   //--- Fill percentage 0..1
   double             fillPercent;

   //--- Lifecycle
   bool               mitigated;
   bool               inverted;
   bool               reacted;

   //--- Original gap still active?
   bool               active;

   //--- Signal already generated from this gap?
   bool               signalUsed;

   //--- IFVG information
   int                inversionDirection;
   datetime           inversionTime;
   int                inversionBar;

   //--- Signal information
   int                signalDirection;
   datetime           signalTime;
   int                signalBar;

   //--- Chart object names
   string             boxName;
   string             midName;
   string             labelName;
   string             ifvgName;
   string             gradeName;

   //--- Constructor
   FVGGap()
     {
      id                 = 0;

      direction          = FVG_DIRECTION_NONE;

      top                = 0.0;
      bottom             = 0.0;

      createdTime        = 0;
      bornBar            = -1;

      grade              = 0.0;

      extreme            = 0.0;
      fillPercent        = 0.0;

      mitigated          = false;
      inverted           = false;
      reacted            = false;

      active              = true;
      signalUsed         = false;

      inversionDirection = FVG_DIRECTION_NONE;
      inversionTime      = 0;
      inversionBar       = -1;

      signalDirection    = FVG_DIRECTION_NONE;
      signalTime         = 0;
      signalBar          = -1;

      boxName            = "";
      midName            = "";
      labelName          = "";
      ifvgName           = "";
      gradeName          = "";
     }

   //--- Gap size
   double Size() const
     {
      return MathAbs(top - bottom);
     }

   //--- Gap midpoint
   double Mid() const
     {
      return (top + bottom) * 0.5;
     }

   //--- Is bullish original FVG?
   bool IsBullish() const
     {
      return direction == FVG_DIRECTION_BULL;
     }

   //--- Is bearish original FVG?
   bool IsBearish() const
     {
      return direction == FVG_DIRECTION_BEAR;
     }

   //--- Is live/unmitigated/non-inverted?
   bool IsLive() const
     {
      return active &&
             !mitigated &&
             !inverted;
     }

   //--- Age in bars
   int Age(const int currentBar) const
     {
      if(bornBar < 0)
         return 0;

      return MathMax(0,
                     currentBar - bornBar);
     }
  };


//+------------------------------------------------------------------+
//| Signal result                                                    |
//+------------------------------------------------------------------+
//
// This is the result produced by the signal engine.
// It does NOT execute trades.
//+------------------------------------------------------------------+

struct FVGSignal
  {
   //--- Valid signal?
   bool               valid;

   //--- Direction
   int                direction;

   //--- Signal type
   bool               isIFVG;

   //--- Text tag
   string             tag;

   //--- Source FVG
   long               sourceGapID;

   //--- FVG boundaries
   double             gapTop;
   double             gapBottom;

   //--- Signal grade
   double             grade;

   //--- Signal candle
   datetime           signalTime;
   int                signalBar;

   //--- Signal price
   double             signalPrice;

   //--- ATR at signal
   double             atr;

   //--- HTF bias
   int                htfBias;

   //--- Constructor
   FVGSignal()
     {
      valid       = false;

      direction   = FVG_DIRECTION_NONE;

      isIFVG      = false;
      tag         = "";

      sourceGapID = 0;

      gapTop      = 0.0;
      gapBottom   = 0.0;

      grade       = 0.0;

      signalTime  = 0;
      signalBar   = -1;

      signalPrice = 0.0;

      atr         = 0.0;

      htfBias     = FVG_DIRECTION_NONE;
     }

   //--- Clear
   void Reset()
     {
      valid       = false;

      direction   = FVG_DIRECTION_NONE;

      isIFVG      = false;
      tag         = "";

      sourceGapID = 0;

      gapTop      = 0.0;
      gapBottom   = 0.0;

      grade       = 0.0;

      signalTime  = 0;
      signalBar   = -1;

      signalPrice = 0.0;

      atr         = 0.0;

      htfBias     = FVG_DIRECTION_NONE;
     }

   //--- Set signal
   void Set(const int dir,
            const bool ifvg,
            const string signalTag,
            const long gapID,
            const double topPrice,
            const double bottomPrice,
            const double signalGrade,
            const datetime time,
            const int bar,
            const double price,
            const double atrValue,
            const int bias)
     {
      valid       = true;

      direction   = dir;

      isIFVG      = ifvg;
      tag         = signalTag;

      sourceGapID = gapID;

      gapTop      = topPrice;
      gapBottom   = bottomPrice;

      grade       = signalGrade;

      signalTime  = time;
      signalBar   = bar;

      signalPrice = price;

      atr         = atrValue;

      htfBias     = bias;
     }
  };


//+------------------------------------------------------------------+
//| Trade blueprint                                                  |
//+------------------------------------------------------------------+
//
// This is the complete mathematical trade model:
//
// Entry
// SL
// Risk
// TP1
// TP2
// TP3
//
// The original risk NEVER changes.
// BE / trailing thresholds are calculated from Original Risk.
//+------------------------------------------------------------------+

struct FVGTradePlan
  {
   //--- Validity
   bool               valid;

   //--- Direction
   int                direction;

   //--- Source signal
   string             signalTag;
   long               sourceGapID;
   double             signalGrade;

   //--- Prices
   double             entry;
   double             stop;
   double             risk;

   double             tp1;
   double             tp2;
   double             tp3;

   //--- Management trigger prices
   double             breakEvenTrigger;
   double             trailTP1Trigger;
   double             trailTP2Trigger;

   //--- ATR
   double             atr;

   //--- Signal bar/time
   datetime           entryTime;
   int                entryBar;

   //--- Trade lifetime
   int                maximumBars;

   //--- Constructor
   FVGTradePlan()
     {
      valid             = false;

      direction         = FVG_DIRECTION_NONE;

      signalTag         = "";
      sourceGapID       = 0;
      signalGrade       = 0.0;

      entry             = 0.0;
      stop              = 0.0;
      risk              = 0.0;

      tp1               = 0.0;
      tp2               = 0.0;
      tp3               = 0.0;

      breakEvenTrigger  = 0.0;
      trailTP1Trigger   = 0.0;
      trailTP2Trigger   = 0.0;

      atr               = 0.0;

      entryTime         = 0;
      entryBar          = -1;

      maximumBars       = 0;
     }

   //--- Reset
   void Reset()
     {
      valid             = false;

      direction         = FVG_DIRECTION_NONE;

      signalTag         = "";
      sourceGapID       = 0;
      signalGrade       = 0.0;

      entry             = 0.0;
      stop              = 0.0;
      risk              = 0.0;

      tp1               = 0.0;
      tp2               = 0.0;
      tp3               = 0.0;

      breakEvenTrigger  = 0.0;
      trailTP1Trigger   = 0.0;
      trailTP2Trigger   = 0.0;

      atr               = 0.0;

      entryTime         = 0;
      entryBar          = -1;

      maximumBars       = 0;
     }

   //--- Calculate R price
   double PriceAtR(const double r) const
     {
      if(direction == FVG_DIRECTION_BULL)
         return entry + risk * r;

      if(direction == FVG_DIRECTION_BEAR)
         return entry - risk * r;

      return entry;
     }

   //--- Current profit in R
   double CurrentR(const double price) const
     {
      if(risk <= FVG_EPSILON)
         return 0.0;

      if(direction == FVG_DIRECTION_BULL)
         return (price - entry) / risk;

      if(direction == FVG_DIRECTION_BEAR)
         return (entry - price) / risk;

      return 0.0;
     }
  };


//+------------------------------------------------------------------+
//| Live trade state                                                 |
//+------------------------------------------------------------------+

struct FVGTradeState
  {
   //--- Is an EA trade currently active?
   bool               active;

   //--- Position ticket
   ulong              ticket;

   //--- Position identifier
   long               positionID;

   //--- Direction
   int                direction;

   //--- Trade plan
   FVGTradePlan       plan;

   //--- Current broker SL
   double             currentSL;

   //--- Current broker TP
   double             currentTP;

   //--- Management flags
   bool               breakEvenDone;
   bool               trailTP1Done;
   bool               trailTP2Done;

   //--- Maximum favorable excursion
   double             maxFavorableR;

   //--- Entry bar
   int                entryBar;

   //--- Entry time
   datetime           entryTime;

   //--- Last management time
   datetime           lastManagementTime;

   //--- Constructor
   FVGTradeState()
     {
      active             = false;

      ticket             = 0;
      positionID         = 0;

      direction          = FVG_DIRECTION_NONE;

      currentSL          = 0.0;
      currentTP          = 0.0;

      breakEvenDone      = false;
      trailTP1Done       = false;
      trailTP2Done       = false;

      maxFavorableR      = 0.0;

      entryBar           = -1;
      entryTime          = 0;

      lastManagementTime = 0;
     }

   //--- Reset
   void Reset()
     {
      active             = false;

      ticket             = 0;
      positionID         = 0;

      direction          = FVG_DIRECTION_NONE;

      plan.Reset();

      currentSL          = 0.0;
      currentTP          = 0.0;

      breakEvenDone      = false;
      trailTP1Done       = false;
      trailTP2Done       = false;

      maxFavorableR      = 0.0;

      entryBar           = -1;
      entryTime          = 0;

      lastManagementTime = 0;
     }

   //--- Current R
   double CurrentR(const double price) const
     {
      return plan.CurrentR(price);
     }
  };


//+------------------------------------------------------------------+
//| Historical trade drawing state                                   |
//+------------------------------------------------------------------+

struct FVGTradeDrawing
  {
   //--- Identification
   long               id;

   //--- Direction
   int                direction;

   //--- Trade prices
   double             entry;
   double             stop;

   double             tp1;
   double             tp2;
   double             tp3;

   //--- Result
   double             resultR;

   //--- Times
   datetime           startTime;
   datetime           endTime;

   //--- Object names
   string             entryName;
   string             stopName;
   string             tp1Name;
   string             tp2Name;
   string             tp3Name;

   string             targetZoneName;
   string             riskZoneName;

   string             entryLabelName;
   string             stopLabelName;
   string             tp1LabelName;
   string             tp2LabelName;
   string             tp3LabelName;

   string             resultLabelName;

   //--- Constructor
   FVGTradeDrawing()
     {
      id               = 0;

      direction        = FVG_DIRECTION_NONE;

      entry            = 0.0;
      stop             = 0.0;

      tp1              = 0.0;
      tp2              = 0.0;
      tp3              = 0.0;

      resultR          = 0.0;

      startTime        = 0;
      endTime          = 0;

      entryName        = "";
      stopName         = "";
      tp1Name          = "";
      tp2Name          = "";
      tp3Name          = "";

      targetZoneName   = "";
      riskZoneName     = "";

      entryLabelName   = "";
      stopLabelName    = "";
      tp1LabelName     = "";
      tp2LabelName     = "";
      tp3LabelName     = "";

      resultLabelName  = "";
     }
  };


//+------------------------------------------------------------------+
//| Dashboard data                                                   |
//+------------------------------------------------------------------+

struct FVGDashData
  {
   //--- HTF
   int                htfBias;

   //--- Active gaps
   int                activeBull;
   int                activeBear;

   //--- Nearest gap
   bool               hasNearestGap;
   double             nearestPrice;
   double             nearestFill;
   int                nearestDirection;

   //--- Strongest gap
   bool               hasStrongestGap;
   double             strongestGrade;
   int                strongestDirection;

   //--- IFVG
   int                lastFlipDirection;
   int                lastFlipBarAge;

   //--- Signal
   bool               hasSignal;
   int                signalDirection;
   string             signalTag;
   double             signalGrade;

   //--- Trade
   bool               tradeActive;
   int                tradeDirection;
   double             tradeEntry;
   double             tradeSL;
   double             tradeTP1;
   double             tradeTP2;
   double             tradeTP3;
   double             tradeCurrentR;

   //--- Account
   double             balance;
   double             equity;

   //--- Statistics
   int                totalBull;
   int                totalBear;
   int                totalInverted;

   //--- Constructor
   FVGDashData()
     {
      Reset();
     }

   //--- Reset
   void Reset()
     {
      htfBias = FVG_DIRECTION_NONE;

      activeBull = 0;
      activeBear = 0;

      hasNearestGap  = false;
      nearestPrice   = 0.0;
      nearestFill    = 0.0;
      nearestDirection = FVG_DIRECTION_NONE;

      hasStrongestGap = false;
      strongestGrade  = 0.0;
      strongestDirection = FVG_DIRECTION_NONE;

      lastFlipDirection = FVG_DIRECTION_NONE;
      lastFlipBarAge    = -1;

      hasSignal      = false;
      signalDirection = FVG_DIRECTION_NONE;
      signalTag      = "";
      signalGrade    = 0.0;

      tradeActive    = false;
      tradeDirection = FVG_DIRECTION_NONE;

      tradeEntry     = 0.0;
      tradeSL       = 0.0;
      tradeTP1      = 0.0;
      tradeTP2      = 0.0;
      tradeTP3      = 0.0;

      tradeCurrentR = 0.0;

      balance       = 0.0;
      equity        = 0.0;

      totalBull     = 0;
      totalBear     = 0;
      totalInverted = 0;
     }
  };


//+------------------------------------------------------------------+
//| Engine statistics                                                |
//+------------------------------------------------------------------+

struct FVGEngineStats
  {
   //--- Lifetime FVG count
   int totalBull;
   int totalBear;

   //--- Inversion count
   int totalInverted;

   //--- Signals
   int totalBuySignals;
   int totalSellSignals;

   //--- Last IFVG
   int lastFlipDirection;
   int lastFlipBar;

   //--- Last signal
   int lastSignalDirection;
   string lastSignalTag;
   int lastSignalBar;

   //--- Constructor
   FVGEngineStats()
     {
      Reset();
     }

   //--- Reset
   void Reset()
     {
      totalBull       = 0;
      totalBear       = 0;

      totalInverted   = 0;

      totalBuySignals = 0;
      totalSellSignals = 0;

      lastFlipDirection = FVG_DIRECTION_NONE;
      lastFlipBar       = -1;

      lastSignalDirection = FVG_DIRECTION_NONE;
      lastSignalTag       = "";
      lastSignalBar       = -1;
     }
  };


//+------------------------------------------------------------------+
//| Candle snapshot                                                  |
//+------------------------------------------------------------------+
//
// Keeps the engine independent from direct indicator calculations.
//+------------------------------------------------------------------+

struct FVGCandle
  {
   datetime           time;

   double             open;
   double             high;
   double             low;
   double             close;

   long               tickVolume;
   long               realVolume;

   //--- Constructor
   FVGCandle()
     {
      time       = 0;

      open       = 0.0;
      high       = 0.0;
      low        = 0.0;
      close      = 0.0;

      tickVolume = 0;
      realVolume = 0;
     }

   //--- Range
   double Range() const
     {
      return MathAbs(high - low);
     }

   //--- Body
   double Body() const
     {
      return MathAbs(close - open);
     }

   //--- Body ratio
   double BodyRatio() const
     {
      double range = Range();

      if(range <= FVG_EPSILON)
         return 0.0;

      return Body() / range;
     }

   //--- Bullish candle
   bool IsBullish() const
     {
      return close > open;
     }

   //--- Bearish candle
   bool IsBearish() const
     {
      return close < open;
     }
  };


//+------------------------------------------------------------------+
//| Indicator snapshot                                               |
//+------------------------------------------------------------------+

struct FVGIndicatorData
  {
   //--- ATR
   double atr;

   //--- Volume average
   double volumeAverage;

   //--- Current volume
   double volume;

   //--- HTF EMA
   double htfEMA;

   //--- HTF close
   double htfClose;

   //--- HTF direction
   int htfBias;

   //--- VWAP
   double vwap;

   //--- VWAP standard deviation
   double vwapStdDev;

   //--- VWAP bands
   double vwapUpper;
   double vwapLower;

   //--- Constructor
   FVGIndicatorData()
     {
      atr            = 0.0;

      volumeAverage  = 0.0;
      volume         = 0.0;

      htfEMA         = 0.0;
      htfClose       = 0.0;
      htfBias        = FVG_DIRECTION_NONE;

      vwap           = 0.0;
      vwapStdDev     = 0.0;

      vwapUpper      = 0.0;
      vwapLower      = 0.0;
     }
  };


//+------------------------------------------------------------------+
//| Chart drawing state                                              |
//+------------------------------------------------------------------+

struct FVGChartState
  {
   //--- Current active trade objects
   string entryLine;
   string stopLine;

   string tp1Line;
   string tp2Line;
   string tp3Line;

   string targetZone;
   string riskZone;

   string signalLabel;

   string entryLabel;
   string stopLabel;

   string tp1Label;
   string tp2Label;
   string tp3Label;

   string exitLabel;

   //--- Active state
   bool tradeObjectsActive;

   //--- Constructor
   FVGChartState()
     {
      Reset();
     }

   //--- Reset
   void Reset()
     {
      entryLine = "";
      stopLine  = "";

      tp1Line = "";
      tp2Line = "";
      tp3Line = "";

      targetZone = "";
      riskZone   = "";

      signalLabel = "";

      entryLabel = "";
      stopLabel  = "";

      tp1Label = "";
      tp2Label = "";
      tp3Label = "";

      exitLabel = "";

      tradeObjectsActive = false;
     }
  };


//+------------------------------------------------------------------+
//| Global engine data                                               |
//+------------------------------------------------------------------+

// These are declared here so every module sees the same state.
//
// The actual engine functions will be implemented in
// FVG_Sniper_Engine.mqh.
//+------------------------------------------------------------------+

FVGEngineStats g_FVGStats;

FVGSignal      g_CurrentSignal;

FVGTradePlan   g_CurrentTradePlan;

FVGTradeState  g_TradeState;

FVGDashData    g_DashboardData;

FVGChartState  g_ChartState;


//+------------------------------------------------------------------+
//| End                                                              |
//+------------------------------------------------------------------+
#endif
