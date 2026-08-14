//+------------------------------------------------------------------+
//|                                                MultiTF_ZoneEA.mq5|
//|                         Multi-Timeframe Zone Confirmation EA     |
//|                                                                  |
//| MONITORING / EXECUTION : M5                                      |
//| TREND                  : H4 / H1 / M15                           |
//| ENTRY ZONES            : H4 / H1 / M15                           |
//| INDICATORS             : M30 / M15 / M5                          |
//|                                                                  |
//| Logic:                                                           |
//| 1. H4/H1/M15 trend must agree.                                   |
//| 2. Price must tap an identified H4/H1/M15 zone.                 |
//| 3. RSI + MACD + Stochastic + Bollinger must all agree           |
//|    on M30, M15 and M5.                                          |
//| 4. Enter once per zone tap.                                     |
//| 5. Maximum 2 EA positions.                                      |
//| 6. SL behind zone +/- configured points.                         |
//| 7. TP = configured R:R (default 1:3).                           |
//| 8. BE and trailing management.                                  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Multi-Timeframe Trend + Zone + Indicator Confirmation EA"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ZoneType
{
   ZONE_SUPPORT = 0,
   ZONE_RESISTANCE,
   ZONE_RBS,
   ZONE_SBR
};

//+------------------------------------------------------------------+
//| STRUCTURES                                                       |
//+------------------------------------------------------------------+
struct ZoneData
{
   bool            valid;
   ENUM_TIMEFRAMES tf;
   ZoneType        type;
   double          price;
   datetime        pivotTime;
   string          name;
};

struct IndicatorState
{
   bool bullish;
   bool bearish;
   bool valid;

   double rsi;

   double macdMain;
   double macdSignal;

   double stochK;
   double stochD;

   double bbMiddle;
   double bbUpper;
   double bbLower;

   double price;
};

struct TFHandles
{
   ENUM_TIMEFRAMES tf;

   int rsi;
   int macd;
   int stoch;
   int bands;

   int ema50;
   int ema200;
};

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+

//--- General
input group "===== GENERAL ====="
input long   InpMagicNumber             = 26081401;
input bool   InpEnableTrading           = true;
input bool   InpOnlyM5Monitoring        = true;
input int    InpMaxOpenTrades           = 2;
input double InpFixedLot                = 0.01;
input int    InpSlippagePoints          = 20;

//--- Trend
input group "===== TREND : H4 / H1 / M15 ====="
input int    InpTrendFastEMA            = 50;
input int    InpTrendSlowEMA            = 200;
input int    InpTrendLookbackBars       = 3;

//--- Zone
input group "===== ZONES : H4 / H1 / M15 ====="
input int    InpFractalLookback         = 250;
input int    InpZoneTouchPoints         = 10;
input int    InpZoneSLBufferPoints      = 10;
input bool   InpUseSupport              = true;
input bool   InpUseResistance           = true;
input bool   InpUseRBS                  = true;
input bool   InpUseSBR                  = true;

//--- RSI
input group "===== RSI ====="
input int    InpRSIPeriod               = 14;
input double InpRSIBuyLevel             = 50.0;
input double InpRSISellLevel            = 50.0;

//--- MACD
input group "===== MACD ====="
input int    InpMACDFast                = 12;
input int    InpMACDSlow                = 26;
input int    InpMACDSignal              = 9;

//--- Stochastic
input group "===== STOCHASTIC ====="
input int    InpStochK                  = 5;
input int    InpStochD                  = 3;
input int    InpStochSlowing            = 3;
input double InpStochBuyLevel           = 50.0;
input double InpStochSellLevel          = 50.0;

//--- Bollinger
input group "===== BOLLINGER BANDS ====="
input int    InpBBPeriod                = 20;
input double InpBBDeviation             = 2.0;

//--- Risk / Trade Manager
input group "===== TRADE MANAGER ====="
input double InpRiskReward              = 3.0;

input bool   InpUseBreakEven            = true;
input double InpBETriggerR              = 1.0;
input double InpBEOffsetPoints          = 0.0;

input bool   InpUseTrailing             = true;
input double InpTrailStartR             = 1.5;
input double InpTrailDistanceR          = 0.5;

//--- Dashboard
input group "===== DASHBOARD ====="
input bool   InpShowDashboard           = true;
input int    InpDashboardX              = 20;
input int    InpDashboardY              = 25;
input int    InpDashboardWidth          = 330;
input int    InpDashboardHeight         = 390;
input int    InpDashboardFont           = 10;
input int    InpDashboardLineHeight     = 20;

//--- Chart Drawing
input group "===== CHART DRAWING ====="
input bool   InpDrawZones               = true;
input bool   InpDrawZoneLabels          = true;
input int    InpZoneWidthPoints         = 20;

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
string PREFIX = "MTF_ZONE_EA_";

ENUM_TIMEFRAMES TrendTFs[3] =
{
   PERIOD_H4,
   PERIOD_H1,
   PERIOD_M15
};

ENUM_TIMEFRAMES IndicatorTFs[3] =
{
   PERIOD_M30,
   PERIOD_M15,
   PERIOD_M5
};

TFHandles g_ind[3];

ZoneData g_zones[12];

int g_zoneCount = 0;

bool g_previousTouch[12];

string g_lastEntryZone = "";

datetime g_lastZoneRefresh = 0;
datetime g_lastDashboardUpdate = 0;

string g_lastSignal = "WAITING";
string g_lastReason = "Waiting for setup";

bool g_lastTrendBull = false;
bool g_lastTrendBear = false;

int g_buyVotes = 0;
int g_sellVotes = 0;

//+------------------------------------------------------------------+
//| COLOR DEFINITIONS                                                |
//+------------------------------------------------------------------+
color CLR_BEIGE       = C'239,228,210';
color CLR_BEIGE_DARK  = C'218,202,179';
color CLR_BROWN       = C'95,72,51';
color CLR_TEXT        = C'55,45,37';

color CLR_GREEN_BG    = C'190,220,190';
color CLR_RED_BG      = C'235,190,190';
color CLR_BLUE_BG     = C'190,210,235';
color CLR_ORANGE_BG   = C'240,215,175';
color CLR_GRAY_BG     = C'215,215,210';

color CLR_GREEN_TEXT  = C'25,100,45';
color CLR_RED_TEXT    = C'150,35,35';

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);

   if(InpOnlyM5Monitoring)
   {
      if(Period() != PERIOD_M5)
      {
         Print("EA is designed to run on M5. Current chart period = ",
               EnumToString((ENUM_TIMEFRAMES)Period()));

         ChartSetSymbolPeriod(
            0,
            _Symbol,
            PERIOD_M5
         );
      }
   }

   if(!CreateIndicatorHandles())
   {
      Print("Failed to create indicator handles.");
      return INIT_FAILED;
   }

   ClearObjects();

   if(InpShowDashboard)
      CreateDashboard();

   RefreshAllZones();
   DrawAllZones();
   UpdateDashboard();

   EventSetTimer(1);

   Print("==========================================");
   Print("MultiTF Zone EA initialized.");
   Print("Symbol : ", _Symbol);
   Print("Magic  : ", InpMagicNumber);
   Print("Lot    : ", InpFixedLot);
   Print("Max    : ", InpMaxOpenTrades);
   Print("RR     : 1:", InpRiskReward);
   Print("==========================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   ReleaseIndicatorHandles();

   ClearObjects();
}

//+------------------------------------------------------------------+
//| TIMER                                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   RefreshAllZones();

   DrawAllZones();

   ManageOpenTrades();

   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| TICK                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageOpenTrades();

   if(!InpEnableTrading)
      return;

   if(InpOnlyM5Monitoring && Period() != PERIOD_M5)
      return;

   if(!IsNewM5Bar())
      return;

   EvaluateEntry();
}

//+------------------------------------------------------------------+
//| CREATE INDICATOR HANDLES                                         |
//+------------------------------------------------------------------+
bool CreateIndicatorHandles()
{
   for(int i = 0; i < 3; i++)
   {
      ENUM_TIMEFRAMES tf = IndicatorTFs[i];

      g_ind[i].tf = tf;

      g_ind[i].rsi =
         iRSI(
            _Symbol,
            tf,
            InpRSIPeriod,
            PRICE_CLOSE
         );

      g_ind[i].macd =
         iMACD(
            _Symbol,
            tf,
            InpMACDFast,
            InpMACDSlow,
            InpMACDSignal,
            PRICE_CLOSE
         );

      g_ind[i].stoch =
         iStochastic(
            _Symbol,
            tf,
            InpStochK,
            InpStochD,
            InpStochSlowing,
            MODE_SMA,
            STO_LOWHIGH
         );

      g_ind[i].bands =
         iBands(
            _Symbol,
            tf,
            InpBBPeriod,
            0,
            InpBBDeviation,
            PRICE_CLOSE
         );

      if(g_ind[i].rsi == INVALID_HANDLE ||
         g_ind[i].macd == INVALID_HANDLE ||
         g_ind[i].stoch == INVALID_HANDLE ||
         g_ind[i].bands == INVALID_HANDLE)
      {
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| RELEASE HANDLES                                                  |
//+------------------------------------------------------------------+
void ReleaseIndicatorHandles()
{
   for(int i = 0; i < 3; i++)
   {
      if(g_ind[i].rsi != INVALID_HANDLE)
         IndicatorRelease(g_ind[i].rsi);

      if(g_ind[i].macd != INVALID_HANDLE)
         IndicatorRelease(g_ind[i].macd);

      if(g_ind[i].stoch != INVALID_HANDLE)
         IndicatorRelease(g_ind[i].stoch);

      if(g_ind[i].bands != INVALID_HANDLE)
         IndicatorRelease(g_ind[i].bands);
   }
}

//+------------------------------------------------------------------+
//| GET BUFFER VALUE                                                 |
//+------------------------------------------------------------------+
bool GetBufferValue(
   int handle,
   int buffer,
   int shift,
   double &value
)
{
   double data[];

   ArraySetAsSeries(data, true);

   if(CopyBuffer(handle, buffer, shift, 1, data) != 1)
      return false;

   value = data[0];

   return true;
}

//+------------------------------------------------------------------+
//| GET PRICE                                                        |
//+------------------------------------------------------------------+
double GetTFPrice(ENUM_TIMEFRAMES tf)
{
   double close[];

   ArraySetAsSeries(close, true);

   if(CopyClose(_Symbol, tf, 1, 1, close) != 1)
      return 0.0;

   return close[0];
}

//+------------------------------------------------------------------+
//| GET INDICATOR STATE                                              |
//+------------------------------------------------------------------+
bool GetIndicatorState(
   int index,
   IndicatorState &state
)
{
   state.valid = false;

   if(index < 0 || index >= 3)
      return false;

   double rsi;
   double macdMain;
   double macdSignal;
   double stochK;
   double stochD;
   double bbMiddle;
   double bbUpper;
   double bbLower;

   if(!GetBufferValue(g_ind[index].rsi, 0, 1, rsi))
      return false;

   if(!GetBufferValue(g_ind[index].macd, 0, 1, macdMain))
      return false;

   if(!GetBufferValue(g_ind[index].macd, 1, 1, macdSignal))
      return false;

   if(!GetBufferValue(g_ind[index].stoch, 0, 1, stochK))
      return false;

   if(!GetBufferValue(g_ind[index].stoch, 1, 1, stochD))
      return false;

   // iBands:
   // 0 = BASE
   // 1 = UPPER
   // 2 = LOWER
   if(!GetBufferValue(g_ind[index].bands, 0, 1, bbMiddle))
      return false;

   if(!GetBufferValue(g_ind[index].bands, 1, 1, bbUpper))
      return false;

   if(!GetBufferValue(g_ind[index].bands, 2, 1, bbLower))
      return false;

   double price = GetTFPrice(g_ind[index].tf);

   if(price <= 0)
      return false;

   state.rsi = rsi;

   state.macdMain = macdMain;
   state.macdSignal = macdSignal;

   state.stochK = stochK;
   state.stochD = stochD;

   state.bbMiddle = bbMiddle;
   state.bbUpper = bbUpper;
   state.bbLower = bbLower;

   state.price = price;

   //===============================================================
   // BULLISH AGREEMENT
   //===============================================================
   bool rsiBull =
      rsi > InpRSIBuyLevel;

   bool macdBull =
      macdMain > macdSignal &&
      macdMain > 0.0;

   bool stochBull =
      stochK > stochD &&
      stochK > InpStochBuyLevel;

   bool bbBull =
      price > bbMiddle;

   //===============================================================
   // BEARISH AGREEMENT
   //===============================================================
   bool rsiBear =
      rsi < InpRSISellLevel;

   bool macdBear =
      macdMain < macdSignal &&
      macdMain < 0.0;

   bool stochBear =
      stochK < stochD &&
      stochK < InpStochSellLevel;

   bool bbBear =
      price < bbMiddle;

   state.bullish =
      rsiBull &&
      macdBull &&
      stochBull &&
      bbBull;

   state.bearish =
      rsiBear &&
      macdBear &&
      stochBear &&
      bbBear;

   state.valid = true;

   return true;
}

//+------------------------------------------------------------------+
//| GET TREND                                                        |
//+------------------------------------------------------------------+
int GetTrend(ENUM_TIMEFRAMES tf)
{
   int fastHandle =
      iMA(
         _Symbol,
         tf,
         InpTrendFastEMA,
         0,
         MODE_EMA,
         PRICE_CLOSE
      );

   int slowHandle =
      iMA(
         _Symbol,
         tf,
         InpTrendSlowEMA,
         0,
         MODE_EMA,
         PRICE_CLOSE
      );

   if(fastHandle == INVALID_HANDLE ||
      slowHandle == INVALID_HANDLE)
   {
      if(fastHandle != INVALID_HANDLE)
         IndicatorRelease(fastHandle);

      if(slowHandle != INVALID_HANDLE)
         IndicatorRelease(slowHandle);

      return 0;
   }

   double fast[];
   double slow[];
   double close[];

   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(close, true);

   int copiedFast =
      CopyBuffer(
         fastHandle,
         0,
         1,
         InpTrendLookbackBars,
         fast
      );

   int copiedSlow =
      CopyBuffer(
         slowHandle,
         0,
         1,
         InpTrendLookbackBars,
         slow
      );

   int copiedClose =
      CopyClose(
         _Symbol,
         tf,
         1,
         InpTrendLookbackBars,
         close
      );

   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);

   if(copiedFast <= 0 ||
      copiedSlow <= 0 ||
      copiedClose <= 0)
   {
      return 0;
   }

   bool up = true;
   bool down = true;

   for(int i = 0; i < copiedFast; i++)
   {
      if(close[i] <= fast[i] ||
         fast[i] <= slow[i])
      {
         up = false;
      }

      if(close[i] >= fast[i] ||
         fast[i] >= slow[i])
      {
         down = false;
      }
   }

   if(up)
      return 1;

   if(down)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| ALL TREND BULLISH                                                |
//+------------------------------------------------------------------+
bool AllTrendBullish()
{
   for(int i = 0; i < 3; i++)
   {
      if(GetTrend(TrendTFs[i]) != 1)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| ALL TREND BEARISH                                                |
//+------------------------------------------------------------------+
bool AllTrendBearish()
{
   for(int i = 0; i < 3; i++)
   {
      if(GetTrend(TrendTFs[i]) != -1)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| CREATE FRACTAL HANDLE                                            |
//+------------------------------------------------------------------+
int CreateFractalHandle(ENUM_TIMEFRAMES tf)
{
   return iFractals(_Symbol, tf);
}

//+------------------------------------------------------------------+
//| GET LATEST FRACTAL LOW                                           |
//+------------------------------------------------------------------+
bool GetLatestFractalLow(
   ENUM_TIMEFRAMES tf,
   double currentPrice,
   double &price,
   datetime &pivotTime
)
{
   int handle = CreateFractalHandle(tf);

   if(handle == INVALID_HANDLE)
      return false;

   double lows[];
   datetime times[];

   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(times, true);

   int copied =
      CopyBuffer(
         handle,
         1,
         2,
         InpFractalLookback,
         lows
      );

   int copiedTime =
      CopyTime(
         _Symbol,
         tf,
         2,
         InpFractalLookback,
         times
      );

   IndicatorRelease(handle);

   if(copied <= 0 || copiedTime <= 0)
      return false;

   int count = MathMin(copied, copiedTime);

   for(int i = 0; i < count; i++)
   {
      if(lows[i] <= 0)
         continue;

      if(lows[i] < currentPrice)
      {
         price = lows[i];
         pivotTime = times[i];
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| GET LATEST FRACTAL HIGH                                          |
//+------------------------------------------------------------------+
bool GetLatestFractalHigh(
   ENUM_TIMEFRAMES tf,
   double currentPrice,
   double &price,
   datetime &pivotTime
)
{
   int handle = CreateFractalHandle(tf);

   if(handle == INVALID_HANDLE)
      return false;

   double highs[];
   datetime times[];

   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(times, true);

   int copied =
      CopyBuffer(
         handle,
         0,
         2,
         InpFractalLookback,
         highs
      );

   int copiedTime =
      CopyTime(
         _Symbol,
         tf,
         2,
         InpFractalLookback,
         times
      );

   IndicatorRelease(handle);

   if(copied <= 0 || copiedTime <= 0)
      return false;

   int count = MathMin(copied, copiedTime);

   for(int i = 0; i < count; i++)
   {
      if(highs[i] <= 0)
         continue;

      if(highs[i] > currentPrice)
      {
         price = highs[i];
         pivotTime = times[i];
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| FIND RBS                                                         |
//| Resistance level that was broken upward and is now support.     |
//+------------------------------------------------------------------+
bool GetLatestRBS(
   ENUM_TIMEFRAMES tf,
   double currentPrice,
   double &price,
   datetime &pivotTime
)
{
   int handle = CreateFractalHandle(tf);

   if(handle == INVALID_HANDLE)
      return false;

   double highs[];
   datetime times[];
   double closes[];

   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(times, true);
   ArraySetAsSeries(closes, true);

   int copied =
      CopyBuffer(
         handle,
         0,
         2,
         InpFractalLookback,
         highs
      );

   int copiedTime =
      CopyTime(
         _Symbol,
         tf,
         2,
         InpFractalLookback,
         times
      );

   int copiedClose =
      CopyClose(
         _Symbol,
         tf,
         1,
         InpFractalLookback + 2,
         closes
      );

   IndicatorRelease(handle);

   if(copied <= 0 ||
      copiedTime <= 0 ||
      copiedClose <= 0)
      return false;

   int count = MathMin(copied, copiedTime);

   // Search newest fractal first.
   for(int i = 0; i < count; i++)
   {
      double level = highs[i];

      if(level <= 0)
         continue;

      if(level >= currentPrice)
         continue;

      bool broken = false;

      // Fractal corresponds approximately to shift i+2.
      // Check more recent bars.
      int maxCheck = MathMin(i + 1, copiedClose - 1);

      for(int j = maxCheck; j >= 0; j--)
      {
         if(closes[j] > level)
         {
            broken = true;
            break;
         }
      }

      if(broken)
      {
         price = level;
         pivotTime = times[i];
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| FIND SBR                                                         |
//| Support level broken downward and now resistance.               |
//+------------------------------------------------------------------+
bool GetLatestSBR(
   ENUM_TIMEFRAMES tf,
   double currentPrice,
   double &price,
   datetime &pivotTime
)
{
   int handle = CreateFractalHandle(tf);

   if(handle == INVALID_HANDLE)
      return false;

   double lows[];
   datetime times[];
   double closes[];

   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(times, true);
   ArraySetAsSeries(closes, true);

   int copied =
      CopyBuffer(
         handle,
         1,
         2,
         InpFractalLookback,
         lows
      );

   int copiedTime =
      CopyTime(
         _Symbol,
         tf,
         2,
         InpFractalLookback,
         times
      );

   int copiedClose =
      CopyClose(
         _Symbol,
         tf,
         1,
         InpFractalLookback + 2,
         closes
      );

   IndicatorRelease(handle);

   if(copied <= 0 ||
      copiedTime <= 0 ||
      copiedClose <= 0)
      return false;

   int count = MathMin(copied, copiedTime);

   for(int i = 0; i < count; i++)
   {
      double level = lows[i];

      if(level <= 0)
         continue;

      if(level <= currentPrice)
         continue;

      bool broken = false;

      int maxCheck = MathMin(i + 1, copiedClose - 1);

      for(int j = maxCheck; j >= 0; j--)
      {
         if(closes[j] < level)
         {
            broken = true;
            break;
         }
      }

      if(broken)
      {
         price = level;
         pivotTime = times[i];
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| ADD ZONE                                                         |
//+------------------------------------------------------------------+
void AddZone(
   ENUM_TIMEFRAMES tf,
   ZoneType type,
   double price,
   datetime pivotTime
)
{
   if(g_zoneCount >= 12)
      return;

   if(price <= 0)
      return;

   ZoneData z;

   z.valid = true;
   z.tf = tf;
   z.type = type;
   z.price = price;
   z.pivotTime = pivotTime;

   string tfName = EnumToString(tf);

   string typeName;

   switch(type)
   {
      case ZONE_SUPPORT:
         typeName = "SUPPORT";
         break;

      case ZONE_RESISTANCE:
         typeName = "RESISTANCE";
         break;

      case ZONE_RBS:
         typeName = "RBS";
         break;

      case ZONE_SBR:
         typeName = "SBR";
         break;
   }

   z.name =
      tfName +
      "_" +
      typeName;

   g_zones[g_zoneCount] = z;

   g_previousTouch[g_zoneCount] = false;

   g_zoneCount++;
}

//+------------------------------------------------------------------+
//| REFRESH ALL ZONES                                                |
//+------------------------------------------------------------------+
void RefreshAllZones()
{
   g_zoneCount = 0;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double currentPrice = (bid + ask) / 2.0;

   for(int i = 0; i < 3; i++)
   {
      ENUM_TIMEFRAMES tf = TrendTFs[i];

      double price;
      datetime pivotTime;

      //============================================================
      // SUPPORT
      //============================================================
      if(InpUseSupport)
      {
         if(GetLatestFractalLow(
               tf,
               currentPrice,
               price,
               pivotTime))
         {
            AddZone(
               tf,
               ZONE_SUPPORT,
               price,
               pivotTime
            );
         }
      }

      //============================================================
      // RESISTANCE
      //============================================================
      if(InpUseResistance)
      {
         if(GetLatestFractalHigh(
               tf,
               currentPrice,
               price,
               pivotTime))
         {
            AddZone(
               tf,
               ZONE_RESISTANCE,
               price,
               pivotTime
            );
         }
      }

      //============================================================
      // RBS
      //============================================================
      if(InpUseRBS)
      {
         if(GetLatestRBS(
               tf,
               currentPrice,
               price,
               pivotTime))
         {
            AddZone(
               tf,
               ZONE_RBS,
               price,
               pivotTime
            );
         }
      }

      //============================================================
      // SBR
      //============================================================
      if(InpUseSBR)
      {
         if(GetLatestSBR(
               tf,
               currentPrice,
               price,
               pivotTime))
         {
            AddZone(
               tf,
               ZONE_SBR,
               price,
               pivotTime
            );
         }
      }
   }

   g_lastZoneRefresh = TimeCurrent();
}

//+------------------------------------------------------------------+
//| ZONE TYPE NAME                                                   |
//+------------------------------------------------------------------+
string ZoneTypeName(ZoneType type)
{
   switch(type)
   {
      case ZONE_SUPPORT:
         return "SUPPORT";

      case ZONE_RESISTANCE:
         return "RESISTANCE";

      case ZONE_RBS:
         return "RBS";

      case ZONE_SBR:
         return "SBR";
   }

   return "ZONE";
}

//+------------------------------------------------------------------+
//| TF SHORT NAME                                                    |
//+------------------------------------------------------------------+
string TFShortName(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_H4:
         return "H4";

      case PERIOD_H1:
         return "H1";

      case PERIOD_M15:
         return "M15";

      case PERIOD_M30:
         return "M30";

      case PERIOD_M5:
         return "M5";
   }

   return EnumToString(tf);
}

//+------------------------------------------------------------------+
//| DRAW ALL ZONES                                                   |
//+------------------------------------------------------------------+
void DrawAllZones()
{
   if(!InpDrawZones)
      return;

   DeleteZoneObjects();

   for(int i = 0; i < g_zoneCount; i++)
   {
      if(!g_zones[i].valid)
         continue;

      DrawZone(
         g_zones[i],
         i
      );
   }
}

//+------------------------------------------------------------------+
//| DRAW ZONE                                                        |
//+------------------------------------------------------------------+
void DrawZone(
   ZoneData &zone,
   int index
)
{
   string base =
      PREFIX +
      "ZONE_" +
      IntegerToString(index);

   datetime time1 = zone.pivotTime;

   datetime time2 =
      TimeCurrent() +
      PeriodSeconds(PERIOD_M5) * 300;

   double upper =
      zone.price +
      InpZoneWidthPoints * _Point;

   double lower =
      zone.price -
      InpZoneWidthPoints * _Point;

   color zoneColor = CLR_GRAY_BG;

   if(zone.type == ZONE_SUPPORT)
      zoneColor = CLR_GREEN_BG;

   if(zone.type == ZONE_RESISTANCE)
      zoneColor = CLR_RED_BG;

   if(zone.type == ZONE_RBS)
      zoneColor = CLR_BLUE_BG;

   if(zone.type == ZONE_SBR)
      zoneColor = CLR_ORANGE_BG;

   string rectName = base + "_RECT";

   ObjectCreate(
      0,
      rectName,
      OBJ_RECTANGLE,
      0,
      time1,
      upper,
      time2,
      lower
   );

   ObjectSetInteger(
      0,
      rectName,
      OBJPROP_COLOR,
      zoneColor
   );

   ObjectSetInteger(
      0,
      rectName,
      OBJPROP_STYLE,
      STYLE_SOLID
   );

   ObjectSetInteger(
      0,
      rectName,
      OBJPROP_WIDTH,
      1
   );

   ObjectSetInteger(
      0,
      rectName,
      OBJPROP_FILL,
      true
   );

   ObjectSetInteger(
      0,
      rectName,
      OBJPROP_BACK,
      true
   );

   if(InpDrawZoneLabels)
   {
      string labelName =
         base +
         "_LABEL";

      string text =
         TFShortName(zone.tf) +
         " " +
         ZoneTypeName(zone.type) +
         "  " +
         DoubleToString(
            zone.price,
            _Digits
         );

      ObjectCreate(
         0,
         labelName,
         OBJ_TEXT,
         0,
         TimeCurrent(),
         zone.price
      );

      ObjectSetString(
         0,
         labelName,
         OBJPROP_TEXT,
         text
      );

      ObjectSetInteger(
         0,
         labelName,
         OBJPROP_COLOR,
         CLR_BROWN
      );

      ObjectSetInteger(
         0,
         labelName,
         OBJPROP_FONTSIZE,
         8
      );

      ObjectSetInteger(
         0,
         labelName,
         OBJPROP_ANCHOR,
         ANCHOR_LEFT
      );
   }
}

//+------------------------------------------------------------------+
//| DELETE ZONE OBJECTS                                              |
//+------------------------------------------------------------------+
void DeleteZoneObjects()
{
   int total = ObjectsTotal(0);

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);

      if(StringFind(name, PREFIX + "ZONE_") == 0)
      {
         ObjectDelete(0, name);
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK ZONE TOUCH                                                 |
//+------------------------------------------------------------------+
bool IsPriceTouchingZone(
   ZoneData &zone
)
{
   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID
      );

   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK
      );

   double tolerance =
      InpZoneTouchPoints * _Point;

   double mid =
      (bid + ask) / 2.0;

   return (
      MathAbs(mid - zone.price) <= tolerance
   );
}

//+------------------------------------------------------------------+
//| CHECK IF ZONE IS BULLISH                                         |
//+------------------------------------------------------------------+
bool IsBullishZone(ZoneData &zone)
{
   if(zone.type == ZONE_SUPPORT)
      return true;

   if(zone.type == ZONE_RBS)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| CHECK IF ZONE IS BEARISH                                         |
//+------------------------------------------------------------------+
bool IsBearishZone(ZoneData &zone)
{
   if(zone.type == ZONE_RESISTANCE)
      return true;

   if(zone.type == ZONE_SBR)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| CHECK INDICATOR AGREEMENT                                        |
//+------------------------------------------------------------------+
bool AllIndicatorsBullish()
{
   g_buyVotes = 0;
   g_sellVotes = 0;

   for(int i = 0; i < 3; i++)
   {
      IndicatorState state;

      if(!GetIndicatorState(i, state))
         return false;

      if(state.bullish)
      {
         g_buyVotes++;
      }
      else if(state.bearish)
      {
         g_sellVotes++;
      }
      else
      {
         return false;
      }
   }

   return g_buyVotes == 3;
}

//+------------------------------------------------------------------+
//| ALL INDICATORS BEARISH                                           |
//+------------------------------------------------------------------+
bool AllIndicatorsBearish()
{
   g_buyVotes = 0;
   g_sellVotes = 0;

   for(int i = 0; i < 3; i++)
   {
      IndicatorState state;

      if(!GetIndicatorState(i, state))
         return false;

      if(state.bullish)
      {
         g_buyVotes++;
      }
      else if(state.bearish)
      {
         g_sellVotes++;
      }
      else
      {
         return false;
      }
   }

   return g_sellVotes == 3;
}

//+------------------------------------------------------------------+
//| COUNT OPEN POSITIONS                                             |
//+------------------------------------------------------------------+
int CountOurPositions()
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
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
         magic == InpMagicNumber)
      {
         count++;
      }
   }

   return count;
}

//+------------------------------------------------------------------+
//| NORMALIZE LOT                                                    |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double minLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MIN
      );

   double maxLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MAX
      );

   double step =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_STEP
      );

   lot =
      MathMax(
         minLot,
         MathMin(
            maxLot,
            lot
         )
      );

   if(step > 0)
      lot =
         MathFloor(
            lot / step
         ) * step;

   return NormalizeDouble(
      lot,
      2
   );
}

//+------------------------------------------------------------------+
//| CALCULATE BUY SL                                                 |
//+------------------------------------------------------------------+
double CalculateBuySL(ZoneData &zone)
{
   double sl =
      zone.price -
      InpZoneSLBufferPoints * _Point;

   return NormalizeDouble(
      sl,
      _Digits
   );
}

//+------------------------------------------------------------------+
//| CALCULATE SELL SL                                                |
//+------------------------------------------------------------------+
double CalculateSellSL(ZoneData &zone)
{
   double sl =
      zone.price +
      InpZoneSLBufferPoints * _Point;

   return NormalizeDouble(
      sl,
      _Digits
   );
}

//+------------------------------------------------------------------+
//| VALIDATE BUY SL                                                  |
//+------------------------------------------------------------------+
bool ValidateBuyStops(
   double entry,
   double &sl,
   double &tp
)
{
   long stopsLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      );

   double minDistance =
      stopsLevel * _Point;

   if(entry - sl < minDistance)
      sl =
         entry -
         minDistance;

   double risk =
      entry - sl;

   if(risk <= 0)
      return false;

   tp =
      entry +
      risk *
      InpRiskReward;

   sl =
      NormalizeDouble(
         sl,
         _Digits
      );

   tp =
      NormalizeDouble(
         tp,
         _Digits
      );

   return true;
}

//+------------------------------------------------------------------+
//| VALIDATE SELL SL                                                 |
//+------------------------------------------------------------------+
bool ValidateSellStops(
   double entry,
   double &sl,
   double &tp
)
{
   long stopsLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      );

   double minDistance =
      stopsLevel * _Point;

   if(sl - entry < minDistance)
      sl =
         entry +
         minDistance;

   double risk =
      sl - entry;

   if(risk <= 0)
      return false;

   tp =
      entry -
      risk *
      InpRiskReward;

   sl =
      NormalizeDouble(
         sl,
         _Digits
      );

   tp =
      NormalizeDouble(
         tp,
         _Digits
      );

   return true;
}

//+------------------------------------------------------------------+
//| EXECUTE BUY                                                      |
//+------------------------------------------------------------------+
bool ExecuteBuy(ZoneData &zone)
{
   if(CountOurPositions() >= InpMaxOpenTrades)
      return false;

   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK
      );

   double sl =
      CalculateBuySL(zone);

   double tp = 0;

   if(!ValidateBuyStops(
         ask,
         sl,
         tp))
   {
      g_lastReason =
         "Invalid BUY stops";

      return false;
   }

   double lot =
      NormalizeLot(
         InpFixedLot
      );

   if(lot <= 0)
      return false;

   string comment =
      "ZONE BUY " +
      TFShortName(zone.tf) +
      " " +
      ZoneTypeName(zone.type);

   bool result =
      trade.Buy(
         lot,
         _Symbol,
         0.0,
         sl,
         tp,
         comment
      );

   if(result)
   {
      g_lastSignal = "BUY";
      g_lastReason =
         zone.name;

      g_lastEntryZone =
         zone.name +
         "_" +
         DoubleToString(
            zone.price,
            _Digits
         );

      Print(
         "BUY opened | Zone=",
         zone.name,
         " | Entry=",
         DoubleToString(ask, _Digits),
         " | SL=",
         DoubleToString(sl, _Digits),
         " | TP=",
         DoubleToString(tp, _Digits)
      );
   }
   else
   {
      g_lastSignal = "BUY FAILED";

      g_lastReason =
         trade.ResultRetcodeDescription();
   }

   return result;
}

//+------------------------------------------------------------------+
//| EXECUTE SELL                                                     |
//+------------------------------------------------------------------+
bool ExecuteSell(ZoneData &zone)
{
   if(CountOurPositions() >= InpMaxOpenTrades)
      return false;

   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID
      );

   double sl =
      CalculateSellSL(zone);

   double tp = 0;

   if(!ValidateSellStops(
         bid,
         sl,
         tp))
   {
      g_lastReason =
         "Invalid SELL stops";

      return false;
   }

   double lot =
      NormalizeLot(
         InpFixedLot
      );

   if(lot <= 0)
      return false;

   string comment =
      "ZONE SELL " +
      TFShortName(zone.tf) +
      " " +
      ZoneTypeName(zone.type);

   bool result =
      trade.Sell(
         lot,
         _Symbol,
         0.0,
         sl,
         tp,
         comment
      );

   if(result)
   {
      g_lastSignal = "SELL";

      g_lastReason =
         zone.name;

      g_lastEntryZone =
         zone.name +
         "_" +
         DoubleToString(
            zone.price,
            _Digits
         );

      Print(
         "SELL opened | Zone=",
         zone.name,
         " | Entry=",
         DoubleToString(bid, _Digits),
         " | SL=",
         DoubleToString(sl, _Digits),
         " | TP=",
         DoubleToString(tp, _Digits)
      );
   }
   else
   {
      g_lastSignal = "SELL FAILED";

      g_lastReason =
         trade.ResultRetcodeDescription();
   }

   return result;
}

//+------------------------------------------------------------------+
//| EVALUATE ENTRY                                                   |
//+------------------------------------------------------------------+
void EvaluateEntry()
{
   if(CountOurPositions() >= InpMaxOpenTrades)
   {
      g_lastSignal = "MAX TRADES";
      g_lastReason =
         IntegerToString(
            InpMaxOpenTrades
         );

      return;
   }

   bool trendBull =
      AllTrendBullish();

   bool trendBear =
      AllTrendBearish();

   g_lastTrendBull = trendBull;
   g_lastTrendBear = trendBear;

   if(!trendBull && !trendBear)
   {
      g_lastSignal = "WAITING";
      g_lastReason =
         "H4/H1/M15 trend not aligned";

      return;
   }

   //===============================================================
   // LOOK FOR A TOUCHED ZONE
   //===============================================================
   for(int i = 0; i < g_zoneCount; i++)
   {
      if(!g_zones[i].valid)
         continue;

      bool touching =
         IsPriceTouchingZone(
            g_zones[i]
         );

      //============================================================
      // Only trigger on the first touch.
      //============================================================
      if(!touching)
      {
         g_previousTouch[i] = false;
         continue;
      }

      if(g_previousTouch[i])
         continue;

      g_previousTouch[i] = true;

      //============================================================
      // BULLISH SETUP
      //============================================================
      if(
         trendBull &&
         IsBullishZone(g_zones[i])
      )
      {
         g_lastSignal = "BUY ZONE TAP";

         if(AllIndicatorsBullish())
         {
            g_lastReason =
               "M30/M15/M5 all BUY";

            string zoneKey =
               g_zones[i].name +
               "_" +
               DoubleToString(
                  g_zones[i].price,
                  _Digits
               );

            if(zoneKey != g_lastEntryZone)
            {
               ExecuteBuy(
                  g_zones[i]
               );
            }
         }
         else
         {
            g_lastReason =
               "Indicators not fully BUY aligned";
         }

         return;
      }

      //============================================================
      // BEARISH SETUP
      //============================================================
      if(
         trendBear &&
         IsBearishZone(g_zones[i])
      )
      {
         g_lastSignal = "SELL ZONE TAP";

         if(AllIndicatorsBearish())
         {
            g_lastReason =
               "M30/M15/M5 all SELL";

            string zoneKey =
               g_zones[i].name +
               "_" +
               DoubleToString(
                  g_zones[i].price,
                  _Digits
               );

            if(zoneKey != g_lastEntryZone)
            {
               ExecuteSell(
                  g_zones[i]
               );
            }
         }
         else
         {
            g_lastReason =
               "Indicators not fully SELL aligned";
         }

         return;
      }
   }

   g_lastSignal = "WAITING";
   g_lastReason = "Waiting for zone tap";
}

//+------------------------------------------------------------------+
//| MANAGE OPEN TRADES                                               |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol =
         PositionGetString(
            POSITION_SYMBOL
         );

      long magic =
         PositionGetInteger(
            POSITION_MAGIC
         );

      if(symbol != _Symbol ||
         magic != InpMagicNumber)
      {
         continue;
      }

      long type =
         PositionGetInteger(
            POSITION_TYPE
         );

      double openPrice =
         PositionGetDouble(
            POSITION_PRICE_OPEN
         );

      double currentSL =
         PositionGetDouble(
            POSITION_SL
         );

      double currentTP =
         PositionGetDouble(
            POSITION_TP
         );

      double currentPrice;

      if(type == POSITION_TYPE_BUY)
      {
         currentPrice =
            SymbolInfoDouble(
               _Symbol,
               SYMBOL_BID
            );
      }
      else
      {
         currentPrice =
            SymbolInfoDouble(
               _Symbol,
               SYMBOL_ASK
            );
      }

      //============================================================
      // Original RISK
      //============================================================
      double originalRisk = 0.0;

      if(currentTP > 0)
      {
         originalRisk =
            MathAbs(
               currentTP -
               openPrice
            ) /
            InpRiskReward;
      }

      if(originalRisk <= 0)
         continue;

      //============================================================
      // CURRENT PROFIT IN PRICE
      //============================================================
      double profitDistance;

      if(type == POSITION_TYPE_BUY)
      {
         profitDistance =
            currentPrice -
            openPrice;
      }
      else
      {
         profitDistance =
            openPrice -
            currentPrice;
      }

      if(profitDistance <= 0)
         continue;

      double currentR =
         profitDistance /
         originalRisk;

      //============================================================
      // BREAK EVEN
      //============================================================
      if(
         InpUseBreakEven &&
         currentR >= InpBETriggerR
      )
      {
         double newSL;

         if(type == POSITION_TYPE_BUY)
         {
            newSL =
               openPrice +
               InpBEOffsetPoints *
               _Point;

            newSL =
               NormalizeDouble(
                  newSL,
                  _Digits
               );

            if(
               currentSL == 0 ||
               newSL > currentSL
            )
            {
               ModifyPositionSL(
                  ticket,
                  newSL,
                  currentTP
               );
            }
         }
         else
         {
            newSL =
               openPrice -
               InpBEOffsetPoints *
               _Point;

            newSL =
               NormalizeDouble(
                  newSL,
                  _Digits
               );

            if(
               currentSL == 0 ||
               newSL < currentSL
            )
            {
               ModifyPositionSL(
                  ticket,
                  newSL,
                  currentTP
               );
            }
         }
      }

      //============================================================
      // TRAILING STOP
      //============================================================
      if(
         InpUseTrailing &&
         currentR >= InpTrailStartR
      )
      {
         double trailDistance =
            originalRisk *
            InpTrailDistanceR;

         double newSL;

         if(type == POSITION_TYPE_BUY)
         {
            newSL =
               currentPrice -
               trailDistance;

            newSL =
               NormalizeDouble(
                  newSL,
                  _Digits
               );

            // Never move SL backwards.
            if(
               currentSL == 0 ||
               newSL > currentSL
            )
            {
               if(newSL < currentPrice)
               {
                  ModifyPositionSL(
                     ticket,
                     newSL,
                     currentTP
                  );
               }
            }
         }
         else
         {
            newSL =
               currentPrice +
               trailDistance;

            newSL =
               NormalizeDouble(
                  newSL,
                  _Digits
               );

            // Never move SL backwards.
            if(
               currentSL == 0 ||
               newSL < currentSL
            )
            {
               if(newSL > currentPrice)
               {
                  ModifyPositionSL(
                     ticket,
                     newSL,
                     currentTP
                  );
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MODIFY POSITION SL                                               |
//+------------------------------------------------------------------+
bool ModifyPositionSL(
   ulong ticket,
   double newSL,
   double tp
)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   string symbol =
      PositionGetString(
         POSITION_SYMBOL
      );

   if(symbol != _Symbol)
      return false;

   bool result =
      trade.PositionModify(
         ticket,
         newSL,
         tp
      );

   if(!result)
   {
      Print(
         "PositionModify failed | Ticket=",
         ticket,
         " | ",
         trade.ResultRetcodeDescription()
      );
   }

   return result;
}

//+------------------------------------------------------------------+
//| NEW M5 BAR                                                       |
//+------------------------------------------------------------------+
bool IsNewM5Bar()
{
   static datetime lastBar = 0;

   datetime currentBar =
      iTime(
         _Symbol,
         PERIOD_M5,
         0
      );

   if(currentBar == 0)
      return false;

   if(currentBar != lastBar)
   {
      lastBar = currentBar;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| DASHBOARD LABEL WRAPPER                                          |
//+------------------------------------------------------------------+
void DrawLabel(
   string name,
   string text,
   int x,
   int y,
   int width,
   int height,
   color textColor,
   color backgroundColor,
   int fontSize
)
{
   string bgName =
      name +
      "_BG";

   //===============================================================
   // BACKGROUND
   //===============================================================
   if(ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(
         0,
         bgName,
         OBJ_RECTANGLE_LABEL,
         0,
         0,
         0
      );
   }

   ObjectSetInteger(
      0,
      bgName,
      OBJPROP_CORNER,
      CORNER_LEFT_UPPER
   );

   ObjectSetInteger(
      0,
      bgName,
      OBJPROP_XDISTANCE,
      x
   );

   ObjectSetInteger(
      0,
      bgName,
      OBJPROP_YDISTANCE,
      y
   );

   ObjectSetInteger(
      0,
      bgName,
      OBJPROP_XSIZE,
      width
   );

   ObjectSetInteger(
      0,
      bgName,
      OBJPROP_YSIZE,
      height
   );

   ObjectSetInteger(
      0,
      bgName,
      OBJPROP_BGCOLOR,
      backgroundColor
   );

   ObjectSetInteger(
      0,
      bgName,
      OBJPROP_BORDER_COLOR,
      CLR_BROWN
   );

   ObjectSetInteger(
      0,
      bgName,
      OBJPROP_COLOR,
      CLR_BROWN
   );

   ObjectSetInteger(
      0,
      bgName,
      OBJPROP_SELECTABLE,
      false
   );

   ObjectSetInteger(
      0,
      bgName,
      OBJPROP_HIDDEN,
      true
   );

   //===============================================================
   // TEXT
   //===============================================================
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(
         0,
         name,
         OBJ_LABEL,
         0,
         0,
         0
      );
   }

   ObjectSetInteger(
      0,
      name,
      OBJPROP_CORNER,
      CORNER_LEFT_UPPER
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_XDISTANCE,
      x + 8
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_YDISTANCE,
      y + 3
   );

   ObjectSetString(
      0,
      name,
      OBJPROP_TEXT,
      text
   );

   ObjectSetString(
      0,
      name,
      OBJPROP_FONT,
      "Arial"
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_FONTSIZE,
      fontSize
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_COLOR,
      textColor
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_SELECTABLE,
      false
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_HIDDEN,
      true
   );
}

//+------------------------------------------------------------------+
//| CREATE DASHBOARD                                                 |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   DrawLabel(
      PREFIX + "TITLE",
      "MULTI-TF ZONE AUTOTRADE",
      InpDashboardX,
      InpDashboardY,
      InpDashboardWidth,
      26,
      CLR_BROWN,
      CLR_BEIGE_DARK,
      11
   );

   DrawLabel(
      PREFIX + "SYMBOL",
      "Symbol",
      InpDashboardX,
      InpDashboardY + 30,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   DrawLabel(
      PREFIX + "TREND",
      "Trend",
      InpDashboardX,
      InpDashboardY + 52,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   DrawLabel(
      PREFIX + "ZONE",
      "Zone",
      InpDashboardX,
      InpDashboardY + 74,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   DrawLabel(
      PREFIX + "IND",
      "Indicators",
      InpDashboardX,
      InpDashboardY + 96,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   DrawLabel(
      PREFIX + "M30",
      "M30",
      InpDashboardX,
      InpDashboardY + 118,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   DrawLabel(
      PREFIX + "M15",
      "M15",
      InpDashboardX,
      InpDashboardY + 140,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   DrawLabel(
      PREFIX + "M5",
      "M5",
      InpDashboardX,
      InpDashboardY + 162,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   DrawLabel(
      PREFIX + "SIGNAL",
      "Signal",
      InpDashboardX,
      InpDashboardY + 190,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_BROWN,
      CLR_ORANGE_BG,
      InpDashboardFont
   );

   DrawLabel(
      PREFIX + "REASON",
      "Reason",
      InpDashboardX,
      InpDashboardY + 212,
      InpDashboardWidth,
      38,
      CLR_TEXT,
      CLR_GRAY_BG,
      9
   );

   DrawLabel(
      PREFIX + "BALANCE",
      "Balance",
      InpDashboardX,
      InpDashboardY + 254,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   DrawLabel(
      PREFIX + "EQUITY",
      "Equity",
      InpDashboardX,
      InpDashboardY + 276,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   DrawLabel(
      PREFIX + "POSITIONS",
      "Positions",
      InpDashboardX,
      InpDashboardY + 298,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   DrawLabel(
      PREFIX + "RR",
      "Risk / Reward",
      InpDashboardX,
      InpDashboardY + 320,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   DrawLabel(
      PREFIX + "STATUS",
      "Status",
      InpDashboardX,
      InpDashboardY + 342,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_BROWN,
      CLR_GREEN_BG,
      InpDashboardFont
   );
}

//+------------------------------------------------------------------+
//| UPDATE DASHBOARD                                                 |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   if(!InpShowDashboard)
      return;

   if(TimeCurrent() == g_lastDashboardUpdate)
      return;

   g_lastDashboardUpdate =
      TimeCurrent();

   //===============================================================
   // SYMBOL
   //===============================================================
   DrawLabel(
      PREFIX + "SYMBOL",
      "Symbol : " + _Symbol +
      "   |   Chart : M5",
      InpDashboardX,
      InpDashboardY + 30,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   //===============================================================
   // TREND
   //===============================================================
   string trendText;

   color trendBG;
   color trendTextColor;

   if(g_lastTrendBull)
   {
      trendText =
         "Trend : H4 ↑  H1 ↑  M15 ↑  | BUY";

      trendBG =
         CLR_GREEN_BG;

      trendTextColor =
         CLR_GREEN_TEXT;
   }
   else if(g_lastTrendBear)
   {
      trendText =
         "Trend : H4 ↓  H1 ↓  M15 ↓  | SELL";

      trendBG =
         CLR_RED_BG;

      trendTextColor =
         CLR_RED_TEXT;
   }
   else
   {
      trendText =
         "Trend : H4/H1/M15 NOT ALIGNED";

      trendBG =
         CLR_GRAY_BG;

      trendTextColor =
         CLR_TEXT;
   }

   DrawLabel(
      PREFIX + "TREND",
      trendText,
      InpDashboardX,
      InpDashboardY + 52,
      InpDashboardWidth,
      InpDashboardLineHeight,
      trendTextColor,
      trendBG,
      InpDashboardFont
   );

   //===============================================================
   // ZONE
   //===============================================================
   string zoneText =
      "Zones : " +
      IntegerToString(g_zoneCount) +
      " identified";

   DrawLabel(
      PREFIX + "ZONE",
      zoneText,
      InpDashboardX,
      InpDashboardY + 74,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   //===============================================================
   // INDICATOR SUMMARY
   //===============================================================
   string indicatorText =
      "Indicators : " +
      IntegerToString(g_buyVotes) +
      " BUY / " +
      IntegerToString(g_sellVotes) +
      " SELL";

   DrawLabel(
      PREFIX + "IND",
      indicatorText,
      InpDashboardX,
      InpDashboardY + 96,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   //===============================================================
   // INDICATORS EACH TF
   //===============================================================
   UpdateIndicatorDashboard(
      0,
      PREFIX + "M30",
      InpDashboardY + 118
   );

   UpdateIndicatorDashboard(
      1,
      PREFIX + "M15",
      InpDashboardY + 140
   );

   UpdateIndicatorDashboard(
      2,
      PREFIX + "M5",
      InpDashboardY + 162
   );

   //===============================================================
   // SIGNAL
   //===============================================================
   color signalBG = CLR_ORANGE_BG;
   color signalText = CLR_BROWN;

   if(
      g_lastSignal == "BUY" ||
      g_lastSignal == "BUY ZONE TAP"
   )
   {
      signalBG = CLR_GREEN_BG;
      signalText = CLR_GREEN_TEXT;
   }

   if(
      g_lastSignal == "SELL" ||
      g_lastSignal == "SELL ZONE TAP"
   )
   {
      signalBG = CLR_RED_BG;
      signalText = CLR_RED_TEXT;
   }

   DrawLabel(
      PREFIX + "SIGNAL",
      "Signal : " + g_lastSignal,
      InpDashboardX,
      InpDashboardY + 190,
      InpDashboardWidth,
      InpDashboardLineHeight,
      signalText,
      signalBG,
      InpDashboardFont
   );

   //===============================================================
   // REASON
   //===============================================================
   DrawLabel(
      PREFIX + "REASON",
      "Reason : " + g_lastReason,
      InpDashboardX,
      InpDashboardY + 212,
      InpDashboardWidth,
      38,
      CLR_TEXT,
      CLR_GRAY_BG,
      9
   );

   //===============================================================
   // BALANCE
   //===============================================================
   double balance =
      AccountInfoDouble(
         ACCOUNT_BALANCE
      );

   DrawLabel(
      PREFIX + "BALANCE",
      "Balance : " +
      DoubleToString(
         balance,
         2
      ),
      InpDashboardX,
      InpDashboardY + 254,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   //===============================================================
   // EQUITY
   //===============================================================
   double equity =
      AccountInfoDouble(
         ACCOUNT_EQUITY
      );

   DrawLabel(
      PREFIX + "EQUITY",
      "Equity  : " +
      DoubleToString(
         equity,
         2
      ),
      InpDashboardX,
      InpDashboardY + 276,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   //===============================================================
   // POSITIONS
   //===============================================================
   int positions =
      CountOurPositions();

   DrawLabel(
      PREFIX + "POSITIONS",
      "Positions : " +
      IntegerToString(positions) +
      " / " +
      IntegerToString(InpMaxOpenTrades),
      InpDashboardX,
      InpDashboardY + 298,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   //===============================================================
   // RR
   //===============================================================
   DrawLabel(
      PREFIX + "RR",
      "Risk / Reward : 1 : " +
      DoubleToString(
         InpRiskReward,
         1
      ),
      InpDashboardX,
      InpDashboardY + 320,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_TEXT,
      CLR_BEIGE,
      InpDashboardFont
   );

   //===============================================================
   // STATUS
   //===============================================================
   string status;

   if(!InpEnableTrading)
      status = "Status : TRADING DISABLED";
   else if(positions >= InpMaxOpenTrades)
      status = "Status : MAX POSITIONS";
   else
      status = "Status : MONITORING M5";

   DrawLabel(
      PREFIX + "STATUS",
      status,
      InpDashboardX,
      InpDashboardY + 342,
      InpDashboardWidth,
      InpDashboardLineHeight,
      CLR_BROWN,
      CLR_GREEN_BG,
      InpDashboardFont
   );
}

//+------------------------------------------------------------------+
//| UPDATE INDICATOR DASHBOARD                                      |
//+------------------------------------------------------------------+
void UpdateIndicatorDashboard(
   int index,
   string objectName,
   int y
)
{
   IndicatorState state;

   if(!GetIndicatorState(index, state))
   {
      DrawLabel(
         objectName,
         TFShortName(
            IndicatorTFs[index]
         ) +
         " : NO DATA",
         InpDashboardX,
         y,
         InpDashboardWidth,
         InpDashboardLineHeight,
         CLR_TEXT,
         CLR_GRAY_BG,
         9
      );

      return;
   }

   string direction;

   color bg;
   color textColor;

   if(state.bullish)
   {
      direction =
         "BUY AGREEMENT";

      bg =
         CLR_GREEN_BG;

      textColor =
         CLR_GREEN_TEXT;
   }
   else if(state.bearish)
   {
      direction =
         "SELL AGREEMENT";

      bg =
         CLR_RED_BG;

      textColor =
         CLR_RED_TEXT;
   }
   else
   {
      direction =
         "MIXED";

      bg =
         CLR_GRAY_BG;

      textColor =
         CLR_TEXT;
   }

   string text =
      TFShortName(
         IndicatorTFs[index]
      ) +
      " : " +
      direction;

   DrawLabel(
      objectName,
      text,
      InpDashboardX,
      y,
      InpDashboardWidth,
      InpDashboardLineHeight,
      textColor,
      bg,
      9
   );
}

//+------------------------------------------------------------------+
//| CLEAR OBJECTS                                                    |
//+------------------------------------------------------------------+
void ClearObjects()
{
   int total =
      ObjectsTotal(0);

   for(int i = total - 1; i >= 0; i--)
   {
      string name =
         ObjectName(
            0,
            i
         );

      if(StringFind(
            name,
            PREFIX
         ) == 0)
      {
         ObjectDelete(
            0,
            name
         );
      }
   }
}

//+------------------------------------------------------------------+
//| END                                                              |
//+------------------------------------------------------------------+
