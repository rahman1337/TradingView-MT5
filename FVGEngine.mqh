//+------------------------------------------------------------------+
//| FVG_Sniper_Engine.mqh                                           |
//|                                                                  |
//| FVG SNIPER [JOAT]                                                |
//| Core FVG engine                                                  |
//|                                                                  |
//| Responsibilities:                                               |
//|   - M5 confirmed-bar processing                                  |
//|   - ATR(14)                                                      |
//|   - Volume average                                               |
//|   - H1 EMA(50) bias                                              |
//|   - Bullish FVG detection                                       |
//|   - Bearish FVG detection                                       |
//|   - FVG grading                                                  |
//|   - FVG fill / mitigation                                        |
//|   - IFVG inversion                                               |
//|   - FVG aging                                                    |
//|   - Maximum visible gap control                                  |
//|                                                                  |
//| Does NOT:                                                        |
//|   - Execute trades                                               |
//|   - Modify broker positions                                      |
//|   - Draw dashboard                                               |
//|   - Manage BE / trailing                                         |
//+------------------------------------------------------------------+
#ifndef __FVG_SNIPER_ENGINE_MQH__
#define __FVG_SNIPER_ENGINE_MQH__

#include "Structures.mqh"

//+------------------------------------------------------------------+
//| Global FVG container                                             |
//+------------------------------------------------------------------+

FVGGap g_FVGGaps[];

//+------------------------------------------------------------------+
//| Indicator handles                                                |
//+------------------------------------------------------------------+

int g_ATRHandle    = INVALID_HANDLE;
int g_HTFEMAHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Engine state                                                     |
//+------------------------------------------------------------------+

datetime g_LastProcessedM5Bar = 0;
int      g_CurrentM5BarIndex   = -1;

bool g_EngineInitialized = false;

//+------------------------------------------------------------------+
//| Internal unique ID                                               |
//+------------------------------------------------------------------+

long g_NextFVGID = 1;


//+------------------------------------------------------------------+
//| ENGINE INITIALIZATION                                            |
//+------------------------------------------------------------------+

bool FVGEngineInitialize()
  {
   Print("==================================================");
   Print("FVG SNIPER [JOAT] ENGINE INITIALIZATION");
   Print("LTF: ", FVGTimeframeText(FVG_LTF));
   Print("HTF: ", FVGTimeframeText(InpHTF));
   Print("HTF EMA: ", InpHTFEMALength);
   Print("ATR Length: ", InpATRLength);
   Print("Min Gap ATR: ", DoubleToString(InpMinGapATR, 2));
   Print("Min Body Ratio: ",
         DoubleToString(InpMinDisplacementBodyRatio, 2));
   Print("Min Grade: ",
         DoubleToString(InpMinSignalGrade, 1));
   Print("==================================================");

   //--- Validate symbol
   if(_Symbol == "")
     {
      Print("FVG Engine ERROR: Invalid symbol.");
      return false;
     }

   //--- Validate inputs
   if(InpATRLength < 1)
     {
      Print("FVG Engine ERROR: ATR length must be >= 1.");
      return false;
     }

   if(InpHTFEMALength < 2)
     {
      Print("FVG Engine ERROR: HTF EMA length must be >= 2.");
      return false;
     }

   //--- ATR handle on M5
   g_ATRHandle =
      iATR(_Symbol,
           FVG_LTF,
           InpATRLength);

   if(g_ATRHandle == INVALID_HANDLE)
     {
      Print("FVG Engine ERROR: Failed to create ATR handle. Error=",
            GetLastError());

      return false;
     }

   //--- HTF EMA handle
   g_HTFEMAHandle =
      iMA(_Symbol,
          InpHTF,
          InpHTFEMALength,
          0,
          MODE_EMA,
          PRICE_CLOSE);

   if(g_HTFEMAHandle == INVALID_HANDLE)
     {
      Print("FVG Engine ERROR: Failed to create HTF EMA handle. Error=",
            GetLastError());

      IndicatorRelease(g_ATRHandle);
      g_ATRHandle = INVALID_HANDLE;

      return false;
     }

   //--- Clear FVG container
   ArrayResize(g_FVGGaps, 0);

   //--- Reset state
   g_LastProcessedM5Bar = 0;
   g_CurrentM5BarIndex  = -1;

   g_NextFVGID = 1;

   g_FVGStats.Reset();

   g_CurrentSignal.Reset();
   g_CurrentTradePlan.Reset();
   g_TradeState.Reset();
   g_DashboardData.Reset();
   g_ChartState.Reset();

   g_EngineInitialized = true;

   Print("FVG Engine initialized successfully.");

   return true;
  }


//+------------------------------------------------------------------+
//| ENGINE DEINITIALIZATION                                          |
//+------------------------------------------------------------------+

void FVGEngineDeinitialize()
  {
   if(g_ATRHandle != INVALID_HANDLE)
     {
      IndicatorRelease(g_ATRHandle);
      g_ATRHandle = INVALID_HANDLE;
     }

   if(g_HTFEMAHandle != INVALID_HANDLE)
     {
      IndicatorRelease(g_HTFEMAHandle);
      g_HTFEMAHandle = INVALID_HANDLE;
     }

   ArrayResize(g_FVGGaps, 0);

   g_EngineInitialized = false;

   Print("FVG Engine deinitialized.");
  }


//+------------------------------------------------------------------+
//| GET M5 RATES                                                     |
//+------------------------------------------------------------------+
//
// We request enough bars to reproduce:
//
// close[1]
// open[1]
// high[1]
// low[1]
// high[2]
// low[2]
//
// Since MT5 series are shift based, when processing the latest
// confirmed candle:
//
// shift 1 = latest confirmed M5 candle
// shift 2 = previous M5 candle
// shift 3 = two candles before latest confirmed candle
//
// Pine:
//
// low > high[2]
//
// becomes:
//
// rates[1].low > rates[3].high
//
// because rates[] is chronological after ArraySetAsSeries(false).
//+------------------------------------------------------------------+

bool FVGEngineGetRates(MqlRates &rates[],
                       const int count)
  {
   ArrayResize(rates, count);

   int copied =
      CopyRates(_Symbol,
                FVG_LTF,
                0,
                count,
                rates);

   if(copied < count)
     {
      Print("FVG Engine WARNING: Not enough M5 rates. Requested=",
            count,
            " Copied=",
            copied,
            " Error=",
            GetLastError());

      return false;
     }

   //--- CopyRates returns oldest -> newest for normal arrays.
   ArraySetAsSeries(rates, false);

   return true;
  }


//+------------------------------------------------------------------+
//| GET CURRENT CONFIRMED BAR TIME                                   |
//+------------------------------------------------------------------+

datetime FVGEngineGetClosedBarTime()
  {
   datetime times[];

   ArrayResize(times, 2);

   int copied =
      CopyTime(_Symbol,
               FVG_LTF,
               0,
               2,
               times);

   if(copied < 2)
      return 0;

   ArraySetAsSeries(times, true);

   //--- shift 1 = latest confirmed M5 candle
   return times[1];
  }


//+------------------------------------------------------------------+
//| CHECK FOR NEW CONFIRMED M5 BAR                                   |
//+------------------------------------------------------------------+

bool FVGEngineIsNewConfirmedBar()
  {
   datetime closedBarTime =
      FVGEngineGetClosedBarTime();

   if(closedBarTime <= 0)
      return false;

   if(closedBarTime == g_LastProcessedM5Bar)
      return false;

   g_LastProcessedM5Bar = closedBarTime;

   return true;
  }


//+------------------------------------------------------------------+
//| GET ATR VALUE                                                    |
//+------------------------------------------------------------------+

double FVGEngineGetATR()
  {
   if(g_ATRHandle == INVALID_HANDLE)
      return 0.0;

   double buffer[];

   ArrayResize(buffer, 2);

   ArraySetAsSeries(buffer, true);

   int copied =
      CopyBuffer(g_ATRHandle,
                 0,
                 1,
                 1,
                 buffer);

   if(copied < 1)
      return 0.0;

   if(buffer[0] <= 0.0)
      return 0.0;

   return buffer[0];
  }


//+------------------------------------------------------------------+
//| GET HTF EMA                                                      |
//+------------------------------------------------------------------+

double FVGEngineGetHTFEMA()
  {
   if(g_HTFEMAHandle == INVALID_HANDLE)
      return 0.0;

   double buffer[];

   ArrayResize(buffer, 2);

   ArraySetAsSeries(buffer, true);

   // shift 1 = confirmed H1 candle
   int copied =
      CopyBuffer(g_HTFEMAHandle,
                 0,
                 1,
                 1,
                 buffer);

   if(copied < 1)
      return 0.0;

   return buffer[0];
  }


//+------------------------------------------------------------------+
//| GET HTF CLOSE                                                    |
//+------------------------------------------------------------------+

double FVGEngineGetHTFClose()
  {
   MqlRates rates[];

   ArrayResize(rates, 2);

   int copied =
      CopyRates(_Symbol,
                InpHTF,
                1,
                1,
                rates);

   if(copied < 1)
      return 0.0;

   return rates[0].close;
  }


//+------------------------------------------------------------------+
//| GET HTF BIAS                                                     |
//+------------------------------------------------------------------+
//
// Pine:
//
// htfDir = request.security(
//     ticker,
//     htfTF,
//     close > ta.ema(close, htfEma) ? 1 : -1,
//     lookahead=barmerge.lookahead_off
// )
//
// We intentionally use the last CLOSED H1 candle to prevent
// intrabar HTF repainting.
//+------------------------------------------------------------------+

int FVGEngineGetHTFBias()
  {
   if(!InpUseHTFBias)
      return FVG_DIRECTION_NONE;

   double ema =
      FVGEngineGetHTFEMA();

   double closePrice =
      FVGEngineGetHTFClose();

   if(ema <= 0.0 || closePrice <= 0.0)
      return FVG_DIRECTION_NONE;

   if(closePrice > ema)
      return FVG_DIRECTION_BULL;

   return FVG_DIRECTION_BEAR;
  }


//+------------------------------------------------------------------+
//| CALCULATE 20 BAR VOLUME AVERAGE                                  |
//+------------------------------------------------------------------+

double FVGEngineGetVolumeAverage()
  {
   MqlRates rates[];

   int required = 22;

   if(!FVGEngineGetRates(rates, required))
      return 0.0;

   double sum = 0.0;
   int count  = 0;

   //--- Use confirmed bars.
   //
   // rates[]:
   // 0 = oldest
   // required-1 = current forming
   //
   // We therefore use the 20 bars immediately before the
   // latest confirmed bar.
   //
   // Latest confirmed = required-2
   //
   // Average range:
   // required-21 ... required-2
   //+------------------------------------------------------------------

   int newestConfirmed =
      required - 2;

   int oldest =
      newestConfirmed - 19;

   for(int i = oldest;
       i <= newestConfirmed;
       i++)
     {
      if(i < 0 || i >= ArraySize(rates))
         continue;

      double volume =
         (double)rates[i].tick_volume;

      if(volume <= 0.0 &&
         rates[i].real_volume > 0)
         volume =
            (double)rates[i].real_volume;

      if(volume > 0.0)
        {
         sum += volume;
         count++;
        }
     }

   if(count <= 0)
      return 0.0;

   return sum / count;
  }


//+------------------------------------------------------------------+
//| GET VOLUME FOR SPECIFIC CONFIRMED CANDLE                         |
//+------------------------------------------------------------------+

double FVGEngineGetVolume(const MqlRates &bar)
  {
   double volume =
      (double)bar.tick_volume;

   if(volume <= 0.0 &&
      bar.real_volume > 0)
      volume =
         (double)bar.real_volume;

   return volume;
  }


//+------------------------------------------------------------------+
//| CALCULATE FVG GRADE                                              |
//+------------------------------------------------------------------+
//
// Pine:
//
// sizeScore = min(gapAtr / 1.0, 1.0)
// dispScore = min(disp3 / 2.0, 1.0)
//
// volScore =
//   hasVol and volAvg > 0
//   ? min(volume[1] / volAvg, 2.0) / 2.0
//   : 0.5
//
// grade =
//   min(10,
//      (sizeScore * .40 +
//       dispScore * .35 +
//       volScore * .25) * 10)
//
// IMPORTANT:
//
// Pine's "volume[1]" refers to the middle displacement candle,
// because the FVG is recognized on the current confirmed bar.
//
// Therefore in MT5:
//
// middle candle = rates[2]
// current candle = rates[1]
// two-back candle = rates[3]
//+------------------------------------------------------------------+

double FVGEngineCalculateGrade(const double gapATR,
                               const double displacementATR,
                               const double volume,
                               const double volumeAverage)
  {
   //--- Gap size score
   double sizeScore =
      MathMin(gapATR / 1.0, 1.0);

   //--- Displacement score
   double displacementScore =
      MathMin(displacementATR / 2.0, 1.0);

   //--- Volume score
   double volumeScore = 0.5;

   bool hasVolume =
      volume > 0.0;

   if(hasVolume &&
      volumeAverage > 0.0)
     {
      volumeScore =
         MathMin(volume / volumeAverage, 2.0) / 2.0;
     }

   //--- Final grade
   double grade =
      (sizeScore * 0.40 +
       displacementScore * 0.35 +
       volumeScore * 0.25) * 10.0;

   return MathMin(10.0, grade);
  }


//+------------------------------------------------------------------+
//| ADD FVG                                                           |
//+------------------------------------------------------------------+

bool FVGEngineAddGap(const int direction,
                     const double top,
                     const double bottom,
                     const int bornBar,
                     const datetime createdTime,
                     const double grade)
  {
   if(direction == FVG_DIRECTION_NONE)
      return false;

   if(top <= bottom)
      return false;

   FVGGap gap;

   gap.id =
      g_NextFVGID++;

   gap.direction =
      direction;

   gap.top =
      top;

   gap.bottom =
      bottom;

   gap.createdTime =
      createdTime;

   gap.bornBar =
      bornBar;

   gap.grade =
      grade;

   //--- Pine:
   //
   // Bull:
   // ext := gTop
   //
   // Bear:
   // ext := gBot
   //
   if(direction == FVG_DIRECTION_BULL)
      gap.extreme = top;
   else
      gap.extreme = bottom;

   gap.fillPercent = 0.0;

   gap.mitigated = false;
   gap.inverted  = false;
   gap.reacted   = false;

   gap.active =
      true;

   gap.signalUsed =
      false;

   //--- Object names are assigned here.
   //--- Actual drawing happens in ChartDrawing.
   string idText =
      LongToString(gap.id);

   if(direction == FVG_DIRECTION_BULL)
     {
      gap.boxName =
         OBJ_FVG_BULL + idText;
     }
   else
     {
      gap.boxName =
         OBJ_FVG_BEAR + idText;
     }

   gap.midName =
      OBJ_FVG_MID + idText;

   gap.labelName =
      OBJ_FVG_LABEL + idText;

   gap.ifvgName =
      OBJ_IFVG + idText;

   gap.gradeName =
      OBJ_GRADE + idText;

   int size =
      ArraySize(g_FVGGaps);

   ArrayResize(g_FVGGaps, size + 1);

   g_FVGGaps[size] =
      gap;

   //--- Lifetime statistics
   if(direction == FVG_DIRECTION_BULL)
      g_FVGStats.totalBull++;
   else
      g_FVGStats.totalBear++;

   return true;
  }


//+------------------------------------------------------------------+
//| DELETE GAP FROM ENGINE ARRAY                                     |
//+------------------------------------------------------------------+
//
// Actual chart-object deletion is intentionally NOT done here.
// ChartDrawing owns chart objects.
//+------------------------------------------------------------------+

void FVGEngineRemoveGap(const int index)
  {
   int size =
      ArraySize(g_FVGGaps);

   if(index < 0 || index >= size)
      return;

   //--- Shift remaining gaps left.
   for(int i = index;
       i < size - 1;
       i++)
     {
      g_FVGGaps[i] =
         g_FVGGaps[i + 1];
     }

   ArrayResize(g_FVGGaps,
               size - 1);
  }


//+------------------------------------------------------------------+
//| UPDATE GAP FILL / MITIGATION / IFVG                              |
//+------------------------------------------------------------------+
//
// This directly follows the supplied Pine logic.
//
// Bullish FVG:
//
//   ext = min(ext, low)
//   fill = (top - ext) / (top - bottom)
//
//   mitigation:
//       low <= bottom
//
//   inversion:
//       close < bottom
//
// Bearish FVG:
//
//   ext = max(ext, high)
//   fill = (ext - bottom) / (top - bottom)
//
//   mitigation:
//       high >= top
//
//   inversion:
//       close > top
//+------------------------------------------------------------------+

void FVGEngineUpdateGap(FVGGap &gap,
                        const MqlRates &bar,
                        const int currentBar)
  {
   if(!gap.active)
      return;

   //--- Once inverted, original gap no longer receives normal
   //--- fill/mitigation processing.
   if(!gap.inverted)
     {
      if(gap.direction == FVG_DIRECTION_BULL)
        {
         //--- Running extreme moves downward.
         gap.extreme =
            MathMin(gap.extreme,
                    bar.low);

         //--- Fill percentage.
         double size =
            MathMax(gap.top - gap.bottom,
                    FVGMinTick(_Symbol));

         gap.fillPercent =
            FVGClamp(
               (gap.top - gap.extreme) / size,
               0.0,
               1.0);

         //--- Full wick mitigation.
         if(bar.low <= gap.bottom)
           {
            gap.mitigated = true;
           }

         //--- Decisive close through bottom = IFVG.
         if(bar.close < gap.bottom)
           {
            gap.inverted = true;

            gap.inversionDirection =
               FVG_DIRECTION_BEAR;

            gap.inversionTime =
               bar.time;

            gap.inversionBar =
               currentBar;

            g_FVGStats.totalInverted++;

            g_FVGStats.lastFlipDirection =
               FVG_DIRECTION_BEAR;

            g_FVGStats.lastFlipBar =
               currentBar;
           }
        }
      else
        if(gap.direction == FVG_DIRECTION_BEAR)
          {
           //--- Running extreme moves upward.
           gap.extreme =
              MathMax(gap.extreme,
                      bar.high);

           //--- Fill percentage.
           double size =
              MathMax(gap.top - gap.bottom,
                      FVGMinTick(_Symbol));

           gap.fillPercent =
              FVGClamp(
                 (gap.extreme - gap.bottom) / size,
                 0.0,
                 1.0);

           //--- Full wick mitigation.
           if(bar.high >= gap.top)
             {
              gap.mitigated = true;
             }

           //--- Decisive close through top = IFVG.
           if(bar.close > gap.top)
             {
              gap.inverted = true;

              gap.inversionDirection =
                 FVG_DIRECTION_BULL;

              gap.inversionTime =
                 bar.time;

              gap.inversionBar =
                 currentBar;

              g_FVGStats.totalInverted++;

              g_FVGStats.lastFlipDirection =
                 FVG_DIRECTION_BULL;

              g_FVGStats.lastFlipBar =
                 currentBar;
             }
          }
     }
  }


//+------------------------------------------------------------------+
//| CHECK GAP AGE                                                    |
//+------------------------------------------------------------------+

bool FVGEngineGapExpired(const FVGGap &gap,
                         const int currentBar)
  {
   int age =
      gap.Age(currentBar);

   return age > InpGapLifetimeBars;
  }


//+------------------------------------------------------------------+
//| ENFORCE MAX GAP COUNT                                            |
//+------------------------------------------------------------------+
//
// Pine:
//
// while array.size(gaps) > maxGaps
//     old = array.shift(gaps)
//
// Therefore the oldest gap is removed first.
//+------------------------------------------------------------------+

void FVGEngineEnforceMaxGaps()
  {
   while(ArraySize(g_FVGGaps) >
         InpMaxVisibleGaps)
     {
      FVGEngineRemoveGap(0);
     }
  }


//+------------------------------------------------------------------+
//| DETECT NEW BULLISH / BEARISH FVG                                 |
//+------------------------------------------------------------------+
//
// IMPORTANT MAPPING:
//
// Pine current confirmed bar:
//
//   current = bar
//   middle  = bar[1]
//   old     = bar[2]
//
// MT5 rates array:
//
//   rates[1] = current confirmed bar
//   rates[2] = middle displacement candle
//   rates[3] = old candle
//
// Bullish:
//   low > high[2]
//
// MT5:
//   rates[1].low > rates[3].high
//
// Bearish:
//   high < low[2]
//
// MT5:
//   rates[1].high < rates[3].low
//
// Body ratio is taken from rates[2].
// Displacement range is also rates[2].
//+------------------------------------------------------------------+

void FVGEngineDetectNewGaps(const MqlRates &rates[],
                            const double atr,
                            const double volumeAverage,
                            const int currentBar)
  {
   if(ArraySize(rates) < 4)
      return;

   //--- Current confirmed M5 candle
   const MqlRates &currentBarData =
      rates[1];

   //--- Middle displacement candle
   const MqlRates &middleBar =
      rates[2];

   //--- Two bars back
   const MqlRates &oldBar =
      rates[3];

   if(atr <= 0.0)
      return;

   //--- Pine:
   //
   // bodyRatio =
   // abs(close[1] - open[1]) /
   // max(high[1] - low[1], mintick)
   //
   // In MT5:
   // middleBar = Pine [1]
   double middleRange =
      MathMax(
         middleBar.high - middleBar.low,
         FVGMinTick(_Symbol));

   double bodyRatio =
      MathAbs(
         middleBar.close -
         middleBar.open) /
      middleRange;

   //--- Pine:
   //
   // disp3 =
   // (high[1] - low[1]) / safeAtr
   //
   double displacementATR =
      (middleBar.high -
       middleBar.low) /
      atr;

   //--- Volume used by Pine = volume[1]
   double middleVolume =
      FVGEngineGetVolume(middleBar);

   //+------------------------------------------------------------------+
   //| Bullish FVG                                                     |
   //+------------------------------------------------------------------+
   //
   // Pine:
   //
   // newBull = allowBull and
   //           not na(high[2]) and
   //           low > high[2]
   //
   // Gap:
   //
   // gTop = low
   // gBot = high[2]
   //
   if(InpAllowBullFVG)
     {
      bool newBull =
         currentBarData.low >
         oldBar.high;

      if(newBull)
        {
         double gTop =
            currentBarData.low;

         double gBottom =
            oldBar.high;

         double gapSize =
            gTop - gBottom;

         double gapATR =
            gapSize / atr;

         //--- Filters
         if(gapATR >= InpMinGapATR &&
            bodyRatio >= InpMinDisplacementBodyRatio)
           {
            double grade =
               FVGEngineCalculateGrade(
                  gapATR,
                  displacementATR,
                  middleVolume,
                  volumeAverage);

            FVGEngineAddGap(
               FVG_DIRECTION_BULL,
               gTop,
               gBottom,
               currentBar,
               currentBarData.time,
               grade);
           }
        }
     }

   //+------------------------------------------------------------------+
   //| Bearish FVG                                                     |
   //+------------------------------------------------------------------+
   //
   // Pine:
   //
   // newBear = allowBear and
   //           not na(low[2]) and
   //           high < low[2]
   //
   // Gap:
   //
   // gTop = low[2]
   // gBot = high
   //
   if(InpAllowBearFVG)
     {
      bool newBear =
         currentBarData.high <
         oldBar.low;

      if(newBear)
        {
         double gTop =
            oldBar.low;

         double gBottom =
            currentBarData.high;

         double gapSize =
            gTop - gBottom;

         double gapATR =
            gapSize / atr;

         //--- Filters
         if(gapATR >= InpMinGapATR &&
            bodyRatio >= InpMinDisplacementBodyRatio)
           {
            double grade =
               FVGEngineCalculateGrade(
                  gapATR,
                  displacementATR,
                  middleVolume,
                  volumeAverage);

            FVGEngineAddGap(
               FVG_DIRECTION_BEAR,
               gTop,
               gBottom,
               currentBar,
               currentBarData.time,
               grade);
           }
        }
     }
  }


//+------------------------------------------------------------------+
//| PROCESS EXISTING GAPS                                            |
//+------------------------------------------------------------------+
//
// This happens BEFORE detection of new gaps, matching Pine.
//+------------------------------------------------------------------+

void FVGEngineProcessExistingGaps(const MqlRates &bar,
                                  const int currentBar)
  {
   int size =
      ArraySize(g_FVGGaps);

   if(size <= 0)
      return;

   //--- Iterate backwards because expired gaps can be removed.
   for(int i = size - 1;
       i >= 0;
       i--)
     {
      if(i >= ArraySize(g_FVGGaps))
         continue;

      FVGGap &gap =
         g_FVGGaps[i];

      //--- Update fill / mitigation / inversion.
      FVGEngineUpdateGap(
         gap,
         bar,
         currentBar);

      //--- Age out.
      if(FVGEngineGapExpired(
            gap,
            currentBar))
        {
         FVGEngineRemoveGap(i);
         continue;
        }
     }
  }


//+------------------------------------------------------------------+
//| GET ACTIVE BULL FVG COUNT                                        |
//+------------------------------------------------------------------+

int FVGEngineActiveBullCount()
  {
   int count = 0;

   int size =
      ArraySize(g_FVGGaps);

   for(int i = 0;
       i < size;
       i++)
     {
      if(g_FVGGaps[i].IsLive() &&
         g_FVGGaps[i].direction ==
         FVG_DIRECTION_BULL)
        {
         count++;
        }
     }

   return count;
  }


//+------------------------------------------------------------------+
//| GET ACTIVE BEAR FVG COUNT                                        |
//+------------------------------------------------------------------+

int FVGEngineActiveBearCount()
  {
   int count = 0;

   int size =
      ArraySize(g_FVGGaps);

   for(int i = 0;
       i < size;
       i++)
     {
      if(g_FVGGaps[i].IsLive() &&
         g_FVGGaps[i].direction ==
         FVG_DIRECTION_BEAR)
        {
         count++;
        }
     }

   return count;
  }


//+------------------------------------------------------------------+
//| GET STRONGEST ACTIVE GAP                                         |
//+------------------------------------------------------------------+

bool FVGEngineGetStrongestGap(FVGGap &result)
  {
   bool found = false;

   double bestGrade = -1.0;

   int size =
      ArraySize(g_FVGGaps);

   for(int i = 0;
       i < size;
       i++)
     {
      if(!g_FVGGaps[i].IsLive())
         continue;

      if(g_FVGGaps[i].grade >
         bestGrade)
        {
         bestGrade =
            g_FVGGaps[i].grade;

         result =
            g_FVGGaps[i];

         found = true;
        }
     }

   return found;
  }


//+------------------------------------------------------------------+
//| GET NEAREST ACTIVE GAP                                           |
//+------------------------------------------------------------------+
//
// Pine uses:
//
// refPx = (top + bot) / 2
// d = abs(close - refPx)
//
// We reproduce that exactly.
//+------------------------------------------------------------------+

bool FVGEngineGetNearestGap(const double price,
                            FVGGap &result)
  {
   bool found = false;

   double nearestDistance =
      DBL_MAX;

   int size =
      ArraySize(g_FVGGaps);

   for(int i = 0;
       i < size;
       i++)
     {
      if(!g_FVGGaps[i].IsLive())
         continue;

      double mid =
         g_FVGGaps[i].Mid();

      double distance =
         MathAbs(price - mid);

      if(!found ||
         distance < nearestDistance)
        {
         nearestDistance =
            distance;

         result =
            g_FVGGaps[i];

         found = true;
        }
     }

   return found;
  }


//+------------------------------------------------------------------+
//| BUILD DASHBOARD DATA                                             |
//+------------------------------------------------------------------+

void FVGEngineUpdateDashboardData(const double price)
  {
   g_DashboardData.Reset();

   //--- HTF
   g_DashboardData.htfBias =
      FVGEngineGetHTFBias();

   //--- Active gaps
   g_DashboardData.activeBull =
      FVGEngineActiveBullCount();

   g_DashboardData.activeBear =
      FVGEngineActiveBearCount();

   //--- Strongest
   FVGGap strongest;

   if(FVGEngineGetStrongestGap(strongest))
     {
      g_DashboardData.hasStrongestGap =
         true;

      g_DashboardData.strongestGrade =
         strongest.grade;

      g_DashboardData.strongestDirection =
         strongest.direction;
     }

   //--- Nearest
   FVGGap nearest;

   if(FVGEngineGetNearestGap(price,
                             nearest))
     {
      g_DashboardData.hasNearestGap =
         true;

      g_DashboardData.nearestPrice =
         nearest.Mid();

      g_DashboardData.nearestFill =
         nearest.fillPercent;

      g_DashboardData.nearestDirection =
         nearest.direction;
     }

   //--- Last IFVG
   g_DashboardData.lastFlipDirection =
      g_FVGStats.lastFlipDirection;

   if(g_FVGStats.lastFlipBar >= 0 &&
      g_CurrentM5BarIndex >= 0)
     {
      g_DashboardData.lastFlipBarAge =
         MathMax(
            0,
            g_CurrentM5BarIndex -
            g_FVGStats.lastFlipBar);
     }
   else
     {
      g_DashboardData.lastFlipBarAge =
         -1;
     }

   //--- Statistics
   g_DashboardData.totalBull =
      g_FVGStats.totalBull;

   g_DashboardData.totalBear =
      g_FVGStats.totalBear;

   g_DashboardData.totalInverted =
      g_FVGStats.totalInverted;

   //--- Account
   g_DashboardData.balance =
      AccountInfoDouble(ACCOUNT_BALANCE);

   g_DashboardData.equity =
      AccountInfoDouble(ACCOUNT_EQUITY);
  }


//+------------------------------------------------------------------+
//| PROCESS ONE CONFIRMED M5 BAR                                     |
//+------------------------------------------------------------------+
//
// This is the main entry point for the engine.
//
// Order:
//
// 1. Confirm new M5 bar
// 2. Load M5 history
// 3. Get ATR
// 4. Get volume average
// 5. Get current bar index
// 6. Update existing FVGs
// 7. Detect NEW FVGs
// 8. Enforce max gap count
// 9. Update dashboard data
//
// Signal generation is intentionally NOT done here.
// PART 4 will handle rejection + IFVG signals.
//+------------------------------------------------------------------+

bool FVGEngineProcess()
  {
   if(!g_EngineInitialized)
      return false;

   //--- Only process once per confirmed M5 bar.
   if(!FVGEngineIsNewConfirmedBar())
      return false;

   //--- Need enough history.
   MqlRates rates[];

   if(!FVGEngineGetRates(rates, 300))
      return false;

   //--- Latest confirmed bar.
   MqlRates currentBar =
      rates[1];

   //--- Build a logical bar index.
   //
   // We use the number of M5 bars available from the start of
   // history. This gives us a stable age counter for the gap
   // lifetime and dashboard.
   //
   int totalBars =
      Bars(_Symbol,
           FVG_LTF);

   if(totalBars <= 0)
      return false;

   g_CurrentM5BarIndex =
      totalBars - 2;

   //--- ATR
   double atr =
      FVGEngineGetATR();

   if(atr <= 0.0)
     {
      Print("FVG Engine WARNING: ATR unavailable.");
      return false;
     }

   //--- Volume average
   double volumeAverage =
      FVGEngineGetVolumeAverage();

   //--- 1. Existing gaps FIRST.
   FVGEngineProcessExistingGaps(
      currentBar,
      g_CurrentM5BarIndex);

   //--- 2. Detect NEW gaps.
   FVGEngineDetectNewGaps(
      rates,
      atr,
      volumeAverage,
      g_CurrentM5BarIndex);

   //--- 3. Cap gap array.
   FVGEngineEnforceMaxGaps();

   //--- 4. Dashboard snapshot.
   FVGEngineUpdateDashboardData(
      currentBar.close);

   return true;
  }


//+------------------------------------------------------------------+
//| GET CURRENT ATR FOR OTHER MODULES                                |
//+------------------------------------------------------------------+

double FVGEngineCurrentATR()
  {
   return FVGEngineGetATR();
  }


//+------------------------------------------------------------------+
//| GET CURRENT HTF BIAS                                             |
//+------------------------------------------------------------------+

int FVGEngineCurrentHTFBias()
  {
   return FVGEngineGetHTFBias();
  }


//+------------------------------------------------------------------+
//| GET GAP COUNT                                                     |
//+------------------------------------------------------------------+

int FVGEngineGapCount()
  {
   return ArraySize(g_FVGGaps);
  }


//+------------------------------------------------------------------+
//| GET GAP BY INDEX                                                  |
//+------------------------------------------------------------------+

bool FVGEngineGetGap(const int index,
                     FVGGap &result)
  {
   if(index < 0 ||
      index >= ArraySize(g_FVGGaps))
      return false;

   result =
      g_FVGGaps[index];

   return true;
  }


//+------------------------------------------------------------------+
//| DEBUG PRINT                                                       |
//+------------------------------------------------------------------+

void FVGEnginePrintGap(const FVGGap &gap)
  {
   Print(
      "FVG #",
      gap.id,
      " | ",
      FVGDirectionText(gap.direction),
      " | Top=",
      DoubleToString(gap.top,
                     _Digits),
      " | Bottom=",
      DoubleToString(gap.bottom,
                     _Digits),
      " | Grade=",
      DoubleToString(gap.grade,
                     1),
      " | Fill=",
      DoubleToString(gap.fillPercent * 100.0,
                     1),
      "%",
      " | Mitigated=",
      gap.mitigated,
      " | Inverted=",
      gap.inverted,
      " | Reacted=",
      gap.reacted);
  }


//+------------------------------------------------------------------+
//| END                                                              |
//+------------------------------------------------------------------+
#endif
