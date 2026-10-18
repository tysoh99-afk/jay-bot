#property strict
#property version   "1.000"
#property description "Demo-first gold-priority multi-symbol MT5 strategy with shared risk controls"

#include <Trade/Trade.mqh>
#include "..\\Include\\GoldFirstSignal.mqh"
#include "..\\Include\\GoldFirstRisk.mqh"

input bool InpEnableGold = true;
input bool InpEnableEURUSD = true;
input bool InpEnableAdditionalSymbols = true;
input string InpAdditionalSymbols = "GBPUSD,USDJPY";
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15;
input ENUM_TIMEFRAMES InpHigherTimeframe = PERIOD_H1;
input GFExitMode InpExitMode = GF_EXIT_FIXED;
input double InpGoldTakeProfit = 10.0;
input double InpGoldStopLoss = 3.0;
input double InpForexTakeProfitATR = 2.5;
input double InpForexStopLossATR = 1.0;
input bool InpUseBreakEven = false;
input double InpBreakEvenAtR = 1.0;
input bool InpUseATRTrailing = false;
input double InpTrailingATRMultiple = 1.5;
input bool InpUseTimeExit = false;
input int InpMaximumHoldHours = 8;
input double InpDefaultRiskPercent = 0.5;
input double InpMaximumGoldRiskPercent = 1.0;
input double InpMaximumTotalRiskPercent = 2.0;
input double InpMaximumDailyLossPercent = 2.0;
input int InpDefaultMaximumOpenPositions = 5;
input int InpDefaultDailyTradeLimit = 20;
input int InpDefaultMaximumPositionsPerSymbol = 1;
input int InpMaximumConsecutiveLosses = 4;
input int InpLossCooldownMinutes = 15;
input int InpScanIntervalSeconds = 5;
input int InpSymbolCooldownMinutes = 15;
input int InpSessionStartHour = 7;
input int InpSessionEndHour = 20;
input bool InpUseSessionFilter = true;
input bool InpUseADX = true;
input int InpADXMinimum = 20;
input int InpRSIBuyMinimum = 50;
input int InpRSIBuyMaximum = 70;
input int InpRSISellMinimum = 30;
input int InpRSISellMaximum = 50;
input double InpPullbackATRTolerance = 0.35;
input double InpMaximumGoldSpread = 0.80;
input double InpMaximumForexSpread = 0.00030;
input double InpMaximumGoldATR = 25.0;
input double InpMaximumForexATR = 0.0040;
input double InpMinimumRewardRisk = 2.0;
input double InpDefaultMinimumSetupScore = 70.0;
input double InpMinimumFreeMarginPercent = 10.0;
input bool InpUseUSDExposureFilter = true;
input bool InpUseNewsFilter = false;
input bool InpClosePositionsOnDailyLoss = false;
input bool InpAutoStartDefault = false;
input long InpMagicNumber = 801016;

struct GFSymbolStatus
{
   string symbol;
   string direction;
   string trend;
   string signal;
   string reason;
   string blocked_reason;
   double spread;
   double rsi;
   double adx;
   bool evaluated;
   bool price_trend;
   bool ema_stack;
   bool higher_timeframe;
   bool pullback;
   bool rsi_confirmation;
   bool candle_confirmation;
   bool adx_confirmation;
   bool spread_acceptable;
   bool volatility_acceptable;
   bool reward_risk_acceptable;
   bool target_clearance_acceptable;
   bool score_acceptable;
   bool risk_limits_available;
   bool reward_risk_applicable;
   bool target_clearance_applicable;
   bool score_applicable;
};

CTrade g_trade;
string g_symbols[];
bool g_symbol_is_gold[];
GFSymbolStatus g_symbol_statuses[];
bool g_running = false;
bool g_auto_start = false;
bool g_gold_enabled = true;
bool g_eurusd_enabled = true;
bool g_extras_enabled = true;
bool g_close_armed = false;
datetime g_close_confirm_until = 0;
datetime g_last_scan_time = 0;
datetime g_last_dashboard_time = 0;
datetime g_last_history_time = 0;
datetime g_last_loss_time = 0;
int g_daily_limit = 20;
int g_max_open_positions = 5;
int g_max_positions_per_symbol = 1;
int g_consecutive_losses = 0;
double g_risk_percent = 0.5;
double g_max_daily_loss_percent = 2.0;
double g_minimum_score = 70.0;
double g_gold_tp_distance = 10.0;
double g_gold_sl_distance = 3.0;
double g_max_gold_spread = 0.80;
double g_max_gold_atr = 25.0;
int g_daily_entries = 0;
int g_wins_today = 0;
int g_losses_today = 0;
double g_closed_today = 0.0;
double g_floating = 0.0;
double g_open_risk = 0.0;
string g_status = "STOPPED";
string g_current_scan_symbol = "-";
string g_last_signal = "-";
string g_last_trade = "-";
string g_last_error = "-";
double g_last_spread = 0.0;
string g_prefix = "GoldFirst_";

color C_BG = C'15,23,31';
color C_PANEL = C'23,34,45';
color C_EDGE = C'48,67,79';
color C_TEXT = C'229,236,240';
color C_MUTED = C'151,169,178';
color C_TEAL = C'34,190,166';
color C_RED = C'214,89,93';
color C_BLUE = C'65,137,197';
color C_GOLD = C'213,169,73';

string GFObject(const string suffix)
{
   return g_prefix + suffix;
}

string GFStateKey(const string suffix)
{
   return "GF_" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" +
          IntegerToString((int)InpMagicNumber) + "_" + suffix;
}

bool GFCreateRect(const string suffix, int x, int y, int width, int height, color fill, color border)
{
   string name = GFObject(suffix);
   if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
      return false;
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, fill);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   return true;
}

bool GFCreateLabel(const string suffix, const string text, int x, int y, int size, color text_color)
{
   string name = GFObject(suffix);
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
      return false;
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_color);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   return true;
}

bool GFCreateButton(const string suffix, const string text, int x, int y, int width, int height, color fill)
{
   string name = GFObject(suffix);
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
      return false;
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, fill);
   ObjectSetInteger(0, name, OBJPROP_COLOR, C_TEXT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, fill);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   return true;
}

bool GFCreateEdit(const string suffix, const string text, int x, int y, int width, int height)
{
   string name = GFObject(suffix);
   if(!ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0))
      return false;
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C_BG);
   ObjectSetInteger(0, name, OBJPROP_COLOR, C_TEXT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C_EDGE);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   return true;
}

void GFSetLabel(const string suffix, const string text, color text_color)
{
   ObjectSetString(0, GFObject(suffix), OBJPROP_TEXT, text);
   ObjectSetInteger(0, GFObject(suffix), OBJPROP_COLOR, text_color);
}

string GFJsonEscape(string value)
{
   StringReplace(value, "\\", "\\\\");
   StringReplace(value, "\"", "\\\"");
   StringReplace(value, "\r", "\\r");
   StringReplace(value, "\n", "\\n");
   return value;
}

void GFWriteStatusFile()
{
   int file = FileOpen("GoldFirstBotStatus.json", FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(file == INVALID_HANDLE)
   {
      g_last_error = "Cannot write MT5 Common Files status snapshot";
      return;
   }

   string timestamp = TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS);
   string symbols_json = "[";
   for(int index = 0; index < ArraySize(g_symbol_statuses); index++)
   {
      GFSymbolStatus item = g_symbol_statuses[index];
      if(index > 0)
         symbols_json += ",";
      symbols_json += "{\"symbol\":\"" + GFJsonEscape(item.symbol) + "\",\"direction\":\"" +
         item.direction + "\",\"trend\":\"" + item.trend + "\",\"signal\":\"" + item.signal +
         "\",\"reason\":\"" + GFJsonEscape(item.reason) + "\",\"blocked_reason\":\"" +
         GFJsonEscape(item.blocked_reason) + "\",\"evaluated\":" + (item.evaluated ? "true" : "false") +
         ",\"spread\":" + DoubleToString(item.spread, 8) + ",\"rsi\":" + DoubleToString(item.rsi, 2) +
         ",\"adx\":" + DoubleToString(item.adx, 2) + ",\"checks\":[";
      symbols_json += "{\"name\":\"Price vs EMA 200\",\"passed\":" + (item.price_trend ? "true" : "false") + "},";
      symbols_json += "{\"name\":\"EMA 50/200 and EMA 20/50 alignment\",\"passed\":" + (item.ema_stack ? "true" : "false") + "},";
      symbols_json += "{\"name\":\"Higher-timeframe trend\",\"passed\":" + (item.higher_timeframe ? "true" : "false") + ",\"required\":false,\"applicable\":true},";
      symbols_json += "{\"name\":\"Pullback detected\",\"passed\":" + (item.pullback ? "true" : "false") + "},";
      symbols_json += "{\"name\":\"RSI confirmation\",\"passed\":" + (item.rsi_confirmation ? "true" : "false") + "},";
      symbols_json += "{\"name\":\"Candle confirmation\",\"passed\":" + (item.candle_confirmation ? "true" : "false") + "},";
      symbols_json += "{\"name\":\"ADX confirmation\",\"passed\":" + (item.adx_confirmation ? "true" : "false") + ",\"required\":" + (InpUseADX ? "true" : "false") + ",\"applicable\":" + (InpUseADX ? "true" : "false") + "},";
      symbols_json += "{\"name\":\"Spread within limit\",\"passed\":" + (item.spread_acceptable ? "true" : "false") + "},";
      symbols_json += "{\"name\":\"ATR within limit\",\"passed\":" + (item.volatility_acceptable ? "true" : "false") + "},";
      symbols_json += "{\"name\":\"Reward/risk minimum\",\"passed\":" + (item.reward_risk_acceptable ? "true" : "false") + ",\"applicable\":" + (item.reward_risk_applicable ? "true" : "false") + "},";
      symbols_json += "{\"name\":\"Target clearance\",\"passed\":" + (item.target_clearance_acceptable ? "true" : "false") + ",\"applicable\":" + (item.target_clearance_applicable ? "true" : "false") + "},";
      symbols_json += "{\"name\":\"Setup score minimum\",\"passed\":" + (item.score_acceptable ? "true" : "false") + ",\"applicable\":" + (item.score_applicable ? "true" : "false") + "},";
      symbols_json += "{\"name\":\"Global risk and safety limits\",\"passed\":" +
         (item.risk_limits_available ? "true" : "false") + "}]}";
   }
   symbols_json += "]";
   string protection = "";
   if(GFDailyLossProtectionActive(InpMagicNumber, g_max_daily_loss_percent))
      protection = "Daily loss protection active";
   else if(GFCountDailyTrades(InpMagicNumber) >= g_daily_limit)
      protection = "Daily trade limit reached";
   else if(GFManagedPositionCount() >= g_max_open_positions)
      protection = "Open position limit reached";

   string status = "{\"updated_at\":\"" + GFJsonEscape(timestamp) + "\",\"updated_epoch\":" +
      IntegerToString((long)TimeGMT()) + ",\"running\":" +
      (g_running ? "true" : "false") + ",\"status\":\"" + GFJsonEscape(g_status) +
      "\",\"connected\":" + (TerminalInfoInteger(TERMINAL_CONNECTED) ? "true" : "false") +
      ",\"symbol\":\"" + GFJsonEscape(g_current_scan_symbol) + "\",\"signal\":\"" +
      GFJsonEscape(g_last_signal) + "\",\"last_trade\":\"" + GFJsonEscape(g_last_trade) +
      "\",\"error\":\"" + GFJsonEscape(g_last_error) + "\",\"safety_block\":\"" +
      GFJsonEscape(protection) + "\",\"spread\":" +
      DoubleToString(g_last_spread, 8) + ",\"positions\":" + IntegerToString(GFManagedPositionCount()) +
      ",\"max_positions\":" + IntegerToString(g_max_open_positions) + ",\"daily_trades\":" +
      IntegerToString(g_daily_entries) + ",\"daily_limit\":" + IntegerToString(g_daily_limit) +
      ",\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) +
      ",\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) +
      ",\"daily_pnl\":" + DoubleToString(g_closed_today + g_floating, 2) +
      ",\"gold_tp\":" + DoubleToString(g_gold_tp_distance, 2) +
      ",\"gold_sl\":" + DoubleToString(g_gold_sl_distance, 2) +
      ",\"strategy\":\"M15 EMA trend pullback\",\"symbols\":" + symbols_json + "}";
   FileWriteString(file, status);
   FileClose(file);
}

void GFProcessDashboardCommand()
{
   string filename = "GoldFirstBot.command";
   if(!FileIsExist(filename, FILE_COMMON))
      return;
   int file = FileOpen(filename, FILE_READ | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(file == INVALID_HANDLE)
      return;
   string command = FileReadString(file);
   FileClose(file);
   FileDelete(filename, FILE_COMMON);
   StringToUpper(command);

   if(command == "START")
   {
      if(GFValidateDashboard() && !GFDailyLossProtectionActive(InpMagicNumber, g_max_daily_loss_percent))
      {
         g_running = true;
         g_status = "RUNNING - WAITING FOR ENTRY";
         GlobalVariableSet(GFStateKey("was_running"), 1.0);
      }
      else
         g_status = "RISK PROTECTION ACTIVE - START REFUSED";
   }
   else if(command == "STOP")
   {
      g_running = false;
      g_status = "STOPPED - EXISTING STOPS ACTIVE";
      GlobalVariableSet(GFStateKey("was_running"), 0.0);
   }
   GlobalVariablesFlush();
}

void GFStoreSymbolStatus(const GFOpportunity &opportunity, const string blocked_reason)
{
   int size = ArraySize(g_symbol_statuses);
   ArrayResize(g_symbol_statuses, size + 1);
   GFSymbolStatus item;
   item.symbol = opportunity.symbol;
   item.direction = opportunity.direction_buy ? "BUY" : "SELL";
   item.trend = opportunity.price_trend && opportunity.ema_stack
      ? (opportunity.direction_buy ? "BULLISH" : "BEARISH") : "MIXED";
   item.signal = opportunity.direction != 0
      ? (opportunity.direction > 0 ? "VALID BUY" : "VALID SELL")
      : opportunity.direction_confirmed ? (opportunity.direction_buy ? "BUY SETUP BLOCKED" : "SELL SETUP BLOCKED")
      : "WAITING FOR ENTRY";
   item.reason = opportunity.reason;
   item.blocked_reason = blocked_reason;
   item.spread = opportunity.spread;
   item.rsi = opportunity.rsi_value;
   item.adx = opportunity.adx_value;
   item.evaluated = opportunity.market_data_available;
   item.price_trend = opportunity.price_trend;
   item.ema_stack = opportunity.ema_stack;
   item.higher_timeframe = opportunity.higher_timeframe;
   item.pullback = opportunity.pullback;
   item.rsi_confirmation = opportunity.rsi_confirmation;
   item.candle_confirmation = opportunity.candle_confirmation;
   item.adx_confirmation = opportunity.adx_confirmation;
   item.spread_acceptable = opportunity.spread_acceptable;
   item.volatility_acceptable = opportunity.volatility_acceptable;
   item.reward_risk_acceptable = opportunity.reward_risk_acceptable;
   item.target_clearance_acceptable = opportunity.target_clearance_acceptable;
   item.score_acceptable = opportunity.score_acceptable;
   item.reward_risk_applicable = opportunity.direction_confirmed;
   item.target_clearance_applicable = opportunity.direction_confirmed && opportunity.reward_risk_acceptable;
   item.score_applicable = opportunity.score_applicable;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   item.risk_limits_available = blocked_reason == "" && equity > 0.0 &&
      !GFDailyLossProtectionActive(InpMagicNumber, g_max_daily_loss_percent) &&
      GFCountDailyTrades(InpMagicNumber) < g_daily_limit &&
      GFManagedPositionCount() < g_max_open_positions &&
      GFOpenRiskMoney(InpMagicNumber) < equity * InpMaximumTotalRiskPercent / 100.0;
   g_symbol_statuses[size] = item;
}

void GFBuildDashboard()
{
   GFCreateRect("Background", 12, 18, 430, 610, C_PANEL, C_EDGE);
   GFCreateRect("Accent", 12, 18, 4, 610, C_GOLD, C_GOLD);
   GFCreateLabel("Title", "GOLD-FIRST  /  MT5 SYSTEM", 30, 32, 12, C_TEXT);
   GFCreateLabel("Subtitle", "DEMO  |  M15 trend pullback", 30, 54, 9, C_MUTED);
   GFCreateLabel("StateCaption", "BOT STATE", 30, 80, 8, C_MUTED);
   GFCreateRect("StatusLight", 16, 98, 9, 9, C_RED, C_RED);
   GFCreateLabel("State", "STOPPED", 32, 96, 11, C_RED);
   GFCreateLabel("ScanCaption", "SCANNING", 210, 80, 8, C_MUTED);
   GFCreateLabel("Scan", "-", 210, 96, 10, C_GOLD);
   GFCreateLabel("Signal", "Signal: -", 30, 120, 9, C_TEXT);
   GFCreateLabel("Spread", "Spread: -", 210, 120, 9, C_TEXT);
   GFCreateLabel("Positions", "EA positions: 0 / 5", 30, 145, 9, C_TEXT);
   GFCreateLabel("Daily", "Today: 0/20  W/L: 0/0", 210, 145, 9, C_TEXT);
   GFCreateLabel("Equity", "Balance / equity: -", 30, 169, 9, C_TEXT);
   GFCreateLabel("Pnl", "Closed / floating: -", 210, 169, 9, C_TEXT);
   GFCreateLabel("Risk", "Open risk: -", 30, 193, 9, C_TEXT);
   GFCreateLabel("Protection", "Protection: READY", 210, 193, 9, C_TEAL);
   GFCreateLabel("ControlsTitle", "CONTROLS", 30, 222, 8, C_MUTED);
   GFCreateButton("Start", "START", 30, 239, 120, 30, C_TEAL);
   GFCreateButton("Stop", "STOP", 160, 239, 120, 30, C_RED);
   GFCreateButton("Auto", "AUTO-START: OFF", 290, 239, 132, 30, C_BLUE);
   GFCreateButton("Close", "CLOSE EA POSITIONS", 30, 277, 392, 28, C_RED);
   GFCreateButton("Gold", "GOLD: ON", 30, 314, 120, 27, C_GOLD);
   GFCreateButton("EUR", "EURUSD: ON", 160, 314, 120, 27, C_BLUE);
   GFCreateButton("Extras", "EXTRAS: ON", 290, 314, 132, 27, C_BLUE);
   GFCreateLabel("DailyLimitLabel", "DAILY LIMIT 1-50", 30, 356, 8, C_MUTED);
   GFCreateEdit("DailyLimit", IntegerToString(g_daily_limit), 134, 348, 48, 23);
   GFCreateLabel("MaxPositionsLabel", "OPEN MAX 1-5", 194, 356, 8, C_MUTED);
   GFCreateEdit("MaxPositions", IntegerToString(g_max_open_positions), 284, 348, 42, 23);
   GFCreateLabel("RiskLabel", "RISK %", 336, 356, 8, C_MUTED);
   GFCreateEdit("RiskPercent", DoubleToString(g_risk_percent, 2), 380, 348, 42, 23);
   GFCreateLabel("LossLimitLabel", "DAILY LOSS %", 30, 393, 8, C_MUTED);
   GFCreateEdit("DailyLossPercent", DoubleToString(g_max_daily_loss_percent, 1), 116, 385, 48, 23);
   GFCreateLabel("ScoreLabel", "MIN SCORE", 194, 393, 8, C_MUTED);
   GFCreateEdit("MinimumScore", DoubleToString(g_minimum_score, 0), 270, 385, 48, 23);
   GFCreateLabel("GoldSettingsTitle", "GOLD RISK SETTINGS  /  PRICE UNITS", 30, 426, 8, C_GOLD);
   GFCreateLabel("GoldTPLabel", "TP", 30, 451, 8, C_MUTED);
   GFCreateEdit("GoldTP", DoubleToString(g_gold_tp_distance, 1), 60, 444, 54, 23);
   GFCreateLabel("GoldSLLabel", "SL", 130, 451, 8, C_MUTED);
   GFCreateEdit("GoldSL", DoubleToString(g_gold_sl_distance, 1), 158, 444, 54, 23);
   GFCreateLabel("GoldSpreadLabel", "SPREAD", 225, 451, 8, C_MUTED);
   GFCreateEdit("GoldSpread", DoubleToString(g_max_gold_spread, 2), 285, 444, 58, 23);
   GFCreateLabel("GoldATRLabel", "MAX ATR", 350, 451, 8, C_MUTED);
   GFCreateEdit("GoldATR", DoubleToString(g_max_gold_atr, 1), 394, 444, 34, 23);
   GFCreateLabel("LastTrade", "Last order: -", 30, 490, 8, C_MUTED);
   GFCreateLabel("Error", "Last error: -", 30, 512, 8, C_MUTED);
   GFCreateLabel("Footer", "No martingale / one position per symbol", 30, 552, 8, C_MUTED);
   ChartRedraw();
}

bool GFResolveSymbol(const string requested, const bool is_gold, string &resolved)
{
   if(SymbolSelect(requested, true))
   {
      resolved = requested;
      return true;
   }
   string wanted = requested;
   StringToUpper(wanted);
   for(int index = 0; index < SymbolsTotal(false); index++)
   {
      string candidate = SymbolName(index, false);
      string upper = candidate;
      StringToUpper(upper);
      bool match = (upper == wanted || StringFind(upper, wanted) == 0);
      if(is_gold)
      {
         bool gold_alias = upper == "GOLD" || StringFind(upper, "GOLD.") == 0 ||
                           StringFind(upper, "GOLDM") == 0 || StringFind(upper, "GOLD#") == 0 ||
                           StringFind(upper, "GOLD_") == 0;
         if(StringFind(upper, "XAU") == 0 || gold_alias)
            match = true;
      }
      if(match && SymbolSelect(candidate, true))
      {
         resolved = candidate;
         return true;
      }
   }
   return false;
}

void GFAddSymbol(const string requested, const bool is_gold)
{
   string resolved = "";
   if(!GFResolveSymbol(requested, is_gold, resolved))
   {
      Print("Symbol unavailable; skipped: ", requested);
      return;
   }
   for(int index = 0; index < ArraySize(g_symbols); index++)
      if(g_symbols[index] == resolved)
         return;
   int size = ArraySize(g_symbols);
   ArrayResize(g_symbols, size + 1);
   ArrayResize(g_symbol_is_gold, size + 1);
   g_symbols[size] = resolved;
   g_symbol_is_gold[size] = is_gold;
}

void GFInitializeSymbols()
{
   ArrayResize(g_symbols, 0);
   ArrayResize(g_symbol_is_gold, 0);
   if(g_gold_enabled)
      GFAddSymbol("XAUUSD", true);
   if(g_eurusd_enabled)
      GFAddSymbol("EURUSD", false);
   if(g_extras_enabled)
   {
      string requested[];
      ushort separator = StringGetCharacter(",", 0);
      int count = StringSplit(InpAdditionalSymbols, separator, requested);
      for(int index = 0; index < count; index++)
      {
         StringTrimLeft(requested[index]);
         StringTrimRight(requested[index]);
         if(StringLen(requested[index]) > 0)
            GFAddSymbol(requested[index], false);
      }
   }
}

bool GFIsManagedPosition()
{
   return PositionGetInteger(POSITION_MAGIC) == InpMagicNumber;
}

int GFManagedPositionCount(const string symbol = "")
{
   int count = 0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !GFIsManagedPosition())
         continue;
      if(symbol == "" || PositionGetString(POSITION_SYMBOL) == symbol)
         count++;
   }
   return count;
}

double GFManagedFloating()
{
   double value = 0.0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(ticket > 0 && PositionSelectByTicket(ticket) && GFIsManagedPosition())
         value += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return value;
}

double GFClosedProfitToday()
{
   double result = 0.0;
   if(!HistorySelect(GFBrokerDayStart(), TimeTradeServer()))
      return result;
   for(int index = 0; index < HistoryDealsTotal(); index++)
   {
      ulong deal = HistoryDealGetTicket(index);
      if(deal == 0 || HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber)
         continue;
      result += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) +
                HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
   }
   return result;
}

bool GFSessionAllowed()
{
   if(!InpUseSessionFilter)
      return true;
   MqlDateTime now;
   TimeToStruct(TimeTradeServer(), now);
   if(InpSessionStartHour <= InpSessionEndHour)
      return now.hour >= InpSessionStartHour && now.hour < InpSessionEndHour;
   return now.hour >= InpSessionStartHour || now.hour < InpSessionEndHour;
}

bool GFHasSymbolCooldown(const string symbol)
{
   string key = GFStateKey("cool_" + symbol);
   if(!GlobalVariableCheck(key))
      return false;
   return TimeTradeServer() - (datetime)GlobalVariableGet(key) < InpSymbolCooldownMinutes * 60;
}

bool GFHasSameCurrencyExposure(const GFOpportunity &candidate)
{
   if(!InpUseUSDExposureFilter)
      return false;
   string candidate_base = SymbolInfoString(candidate.symbol, SYMBOL_CURRENCY_BASE);
   string candidate_profit = SymbolInfoString(candidate.symbol, SYMBOL_CURRENCY_PROFIT);
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !GFIsManagedPosition())
         continue;
      string symbol = PositionGetString(POSITION_SYMBOL);
      if(symbol == candidate.symbol)
         continue;
      string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
      string profit = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
      bool shares_usd = candidate_base == "USD" || candidate_profit == "USD" || base == "USD" || profit == "USD";
      bool same_direction = ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) == (candidate.direction > 0));
      if(shares_usd && same_direction)
         return true;
   }
   return false;
}

bool GFValidateDashboard()
{
   int daily = (int)StringToInteger(ObjectGetString(0, GFObject("DailyLimit"), OBJPROP_TEXT));
   int maximum = (int)StringToInteger(ObjectGetString(0, GFObject("MaxPositions"), OBJPROP_TEXT));
   double risk = StringToDouble(ObjectGetString(0, GFObject("RiskPercent"), OBJPROP_TEXT));
   double daily_loss = StringToDouble(ObjectGetString(0, GFObject("DailyLossPercent"), OBJPROP_TEXT));
   double score = StringToDouble(ObjectGetString(0, GFObject("MinimumScore"), OBJPROP_TEXT));
   double gold_tp = StringToDouble(ObjectGetString(0, GFObject("GoldTP"), OBJPROP_TEXT));
   double gold_sl = StringToDouble(ObjectGetString(0, GFObject("GoldSL"), OBJPROP_TEXT));
   double gold_spread = StringToDouble(ObjectGetString(0, GFObject("GoldSpread"), OBJPROP_TEXT));
   double gold_atr = StringToDouble(ObjectGetString(0, GFObject("GoldATR"), OBJPROP_TEXT));
   if(daily < 1 || daily > 50 || maximum < 1 || maximum > 5 || risk <= 0.0 || risk > 5.0 ||
      daily_loss <= 0.0 || daily_loss > 10.0 || score < 0.0 || score > 100.0 ||
      gold_tp <= 0.0 || gold_sl <= 0.0 || gold_tp / gold_sl < InpMinimumRewardRisk ||
      gold_spread <= 0.0 || gold_atr <= 0.0)
   {
      g_last_error = "Invalid risk/limit input";
      GFSetLabel("Error", "Last error: " + g_last_error, C_RED);
      return false;
   }
   g_daily_limit = daily;
   g_max_open_positions = maximum;
   g_risk_percent = risk;
   g_max_daily_loss_percent = daily_loss;
   g_minimum_score = score;
   g_gold_tp_distance = gold_tp;
   g_gold_sl_distance = gold_sl;
   g_max_gold_spread = gold_spread;
   g_max_gold_atr = gold_atr;
   GlobalVariableSet(GFStateKey("daily_limit"), daily);
   GlobalVariableSet(GFStateKey("max_positions"), maximum);
   GlobalVariableSet(GFStateKey("risk_percent"), risk);
   GlobalVariableSet(GFStateKey("daily_loss"), daily_loss);
   GlobalVariableSet(GFStateKey("minimum_score"), score);
   GlobalVariableSet(GFStateKey("gold_tp"), gold_tp);
   GlobalVariableSet(GFStateKey("gold_sl"), gold_sl);
   GlobalVariableSet(GFStateKey("gold_spread"), gold_spread);
   GlobalVariableSet(GFStateKey("gold_atr"), gold_atr);
   GlobalVariablesFlush();
   return true;
}

void GFSyncControls()
{
   GFSetLabel("Gold", g_gold_enabled ? "GOLD: ON" : "GOLD: OFF", g_gold_enabled ? C_GOLD : C_MUTED);
   GFSetLabel("EUR", g_eurusd_enabled ? "EURUSD: ON" : "EURUSD: OFF", g_eurusd_enabled ? C_BLUE : C_MUTED);
   GFSetLabel("Extras", g_extras_enabled ? "EXTRAS: ON" : "EXTRAS: OFF", g_extras_enabled ? C_BLUE : C_MUTED);
   GFSetLabel("Auto", g_auto_start ? "AUTO-START: ON" : "AUTO-START: OFF", g_auto_start ? C_TEAL : C_MUTED);
}

void GFRefreshDashboard()
{
   int positions = GFManagedPositionCount();
   int daily_entries = GFCountDailyTrades(InpMagicNumber);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double start_equity = GFDayStartingEquity(InpMagicNumber);
   double daily_loss = start_equity > 0.0 ? (start_equity - equity) / start_equity * 100.0 : 0.0;
   double risk_percent = equity > 0.0 ? g_open_risk / equity * 100.0 : 0.0;
   color state_color = g_running ? C_TEAL : C_RED;
   if(StringFind(g_status, "CONNECTION ERROR") >= 0 || StringFind(g_status, "ERROR") >= 0)
      state_color = C_RED;
   else if(StringFind(g_status, "PROTECTION") >= 0 || StringFind(g_status, "LIMIT") >= 0 ||
           StringFind(g_status, "BLOCKED") >= 0)
      state_color = C_GOLD;
   GFSetLabel("State", g_status, state_color);
   ObjectSetInteger(0, GFObject("StatusLight"), OBJPROP_BGCOLOR, state_color);
   ObjectSetInteger(0, GFObject("StatusLight"), OBJPROP_COLOR, state_color);
   GFSetLabel("Scan", g_current_scan_symbol, C_GOLD);
   GFSetLabel("Signal", "Signal: " + g_last_signal, C_TEXT);
   GFSetLabel("Spread", "Spread: " + DoubleToString(g_last_spread, 5), C_TEXT);
   GFSetLabel("Positions", "EA positions: " + IntegerToString(positions) + " / " + IntegerToString(g_max_open_positions), C_TEXT);
   GFSetLabel("Daily", "Today: " + IntegerToString(daily_entries) + "/" + IntegerToString(g_daily_limit) +
              "  W/L: " + IntegerToString(g_wins_today) + "/" + IntegerToString(g_losses_today), C_TEXT);
   GFSetLabel("Equity", "Balance / equity: " + DoubleToString(balance, 2) + " / " + DoubleToString(equity, 2), C_TEXT);
   GFSetLabel("Pnl", "Closed / floating: " + DoubleToString(g_closed_today, 2) + " / " + DoubleToString(g_floating, 2), C_TEXT);
   GFSetLabel("Risk", "Open risk: " + DoubleToString(risk_percent, 2) + "% / " + DoubleToString(InpMaximumTotalRiskPercent, 2) + "%", C_TEXT);
   bool protected_day = GFDailyLossProtectionActive(InpMagicNumber, g_max_daily_loss_percent);
   GFSetLabel("Protection", protected_day ? "PROTECTION ACTIVE" : "Protection: READY", protected_day ? C_RED : C_TEAL);
   GFSetLabel("LastTrade", "Last trade: " + g_last_trade, C_MUTED);
   GFSetLabel("Error", "Last error: " + g_last_error, StringLen(g_last_error) > 1 ? C_RED : C_MUTED);
   GFSyncControls();
   ChartRedraw();
}

void GFLogTrade(const string event_name, const GFOpportunity &opportunity, const double volume, const string note)
{
   int file = FileOpen("GoldFirstBot.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_SHARE_READ | FILE_COMMON, ',');
   if(file == INVALID_HANDLE)
      return;
   if(FileSize(file) == 0)
      FileWrite(file, "time", "event", "symbol", "direction", "score", "volume", "entry", "sl", "tp", "note");
   FileSeek(file, 0, SEEK_END);
   FileWrite(file, TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS), event_name, opportunity.symbol,
             opportunity.direction > 0 ? "BUY" : "SELL", DoubleToString(opportunity.score, 1),
             DoubleToString(volume, 2), DoubleToString(opportunity.entry, (int)SymbolInfoInteger(opportunity.symbol, SYMBOL_DIGITS)),
             DoubleToString(opportunity.stop_loss, (int)SymbolInfoInteger(opportunity.symbol, SYMBOL_DIGITS)),
             DoubleToString(opportunity.take_profit, (int)SymbolInfoInteger(opportunity.symbol, SYMBOL_DIGITS)), note);
   FileClose(file);
}

void GFLogClosedPosition(const ulong position_id, const string symbol, const string direction, const double volume, const double net)
{
   int file = FileOpen("GoldFirstBotResults.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_SHARE_READ | FILE_COMMON, ',');
   if(file == INVALID_HANDLE)
      return;
   if(FileSize(file) == 0)
      FileWrite(file, "time", "position_id", "symbol", "direction", "volume", "net_profit", "currency");
   FileSeek(file, 0, SEEK_END);
   FileWrite(file, TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS), (string)position_id, symbol,
             direction, DoubleToString(volume, 2), DoubleToString(net, 2), AccountInfoString(ACCOUNT_CURRENCY));
   FileClose(file);
}

int GFBuildCandidates(GFOpportunity &candidates[])
{
   ArrayResize(candidates, 0);
   ArrayResize(g_symbol_statuses, 0);
   for(int index = 0; index < ArraySize(g_symbols); index++)
   {
      string symbol = g_symbols[index];
      bool is_gold = g_symbol_is_gold[index];
      g_current_scan_symbol = symbol;
      double maximum_spread = is_gold ? g_max_gold_spread : InpMaximumForexSpread;
      double maximum_atr = is_gold ? g_max_gold_atr : InpMaximumForexATR;
      GFOpportunity opportunity;
      bool valid = GFBuildOpportunity(symbol, is_gold, InpTimeframe, InpHigherTimeframe, 14, 14, 14, InpUseADX,
                                      InpADXMinimum, InpRSIBuyMinimum, InpRSIBuyMaximum,
                                      InpRSISellMinimum, InpRSISellMaximum, InpPullbackATRTolerance,
                                      maximum_spread, maximum_atr, g_gold_tp_distance, g_gold_sl_distance,
                                      InpExitMode, InpForexTakeProfitATR, InpForexStopLossATR,
                                      InpMinimumRewardRisk, g_minimum_score, opportunity);
      string blocked_reason = "";
      if(GFManagedPositionCount(symbol) >= g_max_positions_per_symbol)
         blocked_reason = "Position already open for symbol";
      else if(GFHasSymbolCooldown(symbol))
         blocked_reason = "Symbol cooldown active";
      GFStoreSymbolStatus(opportunity, blocked_reason);

      if(blocked_reason != "")
         continue;
      if(!valid)
      {
         g_last_error = opportunity.reason;
         continue;
      }
      int size = ArraySize(candidates);
      ArrayResize(candidates, size + 1);
      candidates[size] = opportunity;
   }
   return ArraySize(candidates);
}

int GFBestCandidate(const GFOpportunity &candidates[])
{
   int best = -1;
   for(int index = 0; index < ArraySize(candidates); index++)
   {
      if(best < 0 || candidates[index].score > candidates[best].score + 5.0)
      {
         best = index;
         continue;
      }
      bool candidate_gold = StringFind(candidates[index].symbol, "XAU") >= 0 || StringFind(candidates[index].symbol, "GOLD") >= 0;
      bool best_gold = StringFind(candidates[best].symbol, "XAU") >= 0 || StringFind(candidates[best].symbol, "GOLD") >= 0;
      if(MathAbs(candidates[index].score - candidates[best].score) <= 5.0 && candidate_gold && !best_gold)
         best = index;
   }
   return best;
}

bool GFOpenCandidate(GFOpportunity &opportunity)
{
   if(GFManagedPositionCount() >= g_max_open_positions)
   {
      g_last_error = "Open position limit reached";
      return false;
   }
   if(GFManagedPositionCount(opportunity.symbol) >= g_max_positions_per_symbol)
   {
      g_last_error = "Symbol position limit reached";
      return false;
   }
   if(GFHasSameCurrencyExposure(opportunity))
   {
      g_last_error = "Shared USD exposure filter";
      GFLogTrade("REJECT", opportunity, 0.0, g_last_error);
      return false;
   }
   double volume = 0.0;
   double risk_money = 0.0;
   if(!GFCalculateVolume(opportunity.symbol, opportunity.direction, opportunity.entry, opportunity.stop_loss,
                         InpMagicNumber, g_risk_percent, InpMaximumTotalRiskPercent,
                         InpMinimumFreeMarginPercent, volume, risk_money))
   {
      g_last_error = "Risk budget or margin insufficient";
      GFLogTrade("REJECT", opportunity, 0.0, g_last_error);
      return false;
   }
   string risk_symbol = opportunity.symbol;
   StringToUpper(risk_symbol);
   bool is_gold = StringFind(risk_symbol, "XAU") >= 0 || StringFind(risk_symbol, "GOLD") >= 0;
   if(is_gold && risk_money > AccountInfoDouble(ACCOUNT_EQUITY) * InpMaximumGoldRiskPercent / 100.0)
   {
      g_last_error = "Gold-specific risk ceiling exceeded";
      GFLogTrade("REJECT", opportunity, volume, g_last_error);
      return false;
   }
   double point = SymbolInfoDouble(opportunity.symbol, SYMBOL_POINT);
   long minimum_stops = SymbolInfoInteger(opportunity.symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(MathAbs(opportunity.entry - opportunity.stop_loss) < minimum_stops * point ||
      MathAbs(opportunity.take_profit - opportunity.entry) < minimum_stops * point)
   {
      g_last_error = "Broker minimum stop distance rejects configured exit";
      GFLogTrade("REJECT", opportunity, volume, g_last_error);
      return false;
   }

   g_trade.SetTypeFillingBySymbol(opportunity.symbol);
   bool sent = opportunity.direction > 0
      ? g_trade.Buy(volume, opportunity.symbol, 0.0, opportunity.stop_loss, opportunity.take_profit, "GoldFirst")
      : g_trade.Sell(volume, opportunity.symbol, 0.0, opportunity.stop_loss, opportunity.take_profit, "GoldFirst");
   uint retcode = g_trade.ResultRetcode();
   if(!sent || (retcode != TRADE_RETCODE_DONE && retcode != TRADE_RETCODE_DONE_PARTIAL &&
                retcode != TRADE_RETCODE_PLACED))
   {
      g_last_error = g_trade.ResultRetcodeDescription();
      GFLogTrade("REJECT", opportunity, volume, g_last_error);
      return false;
   }

   GlobalVariableSet(GFStateKey("cool_" + opportunity.symbol), (double)TimeTradeServer());
   GlobalVariablesFlush();
   g_last_signal = (opportunity.direction > 0 ? "BUY " : "SELL ") + opportunity.symbol +
                   " score " + DoubleToString(opportunity.score, 0);
   g_last_trade = (retcode == TRADE_RETCODE_PLACED ? "REQUEST " : "EXECUTED ") +
                  (opportunity.direction > 0 ? "BUY " : "SELL ") + opportunity.symbol +
                  " @ " + DoubleToString(opportunity.entry, (int)SymbolInfoInteger(opportunity.symbol, SYMBOL_DIGITS));
   g_last_error = "-";
   GFLogTrade("OPEN", opportunity, volume, opportunity.reason);
   g_status = retcode == TRADE_RETCODE_PLACED ? "TRADE REQUEST SUBMITTED" : "TRADE EXECUTED";
   return true;
}

void GFManageOpenPositions()
{
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !GFIsManagedPosition())
         continue;
      string symbol = PositionGetString(POSITION_SYMBOL);
      bool is_buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl = PositionGetDouble(POSITION_SL);
      double current_tp = PositionGetDouble(POSITION_TP);
      double volume = PositionGetDouble(POSITION_VOLUME);
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);

      if(InpUseTimeExit && InpMaximumHoldHours > 0 && TimeTradeServer() - open_time >= InpMaximumHoldHours * 3600)
      {
         if(!g_trade.PositionClose(ticket))
            g_last_error = "Time exit failed: " + g_trade.ResultRetcodeDescription();
         else
            g_last_trade = symbol + " time-exit requested";
         continue;
      }
      if(current_sl <= 0.0 || current_tp <= 0.0)
      {
         g_status = "UNPROTECTED EA POSITION - CHECK JOURNAL";
         g_last_error = "Managed position lacks broker SL/TP: " + symbol;
         continue;
      }

      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick))
         continue;
      double new_sl = current_sl;
      double initial_risk = MathAbs(open_price - current_sl);
      double current_price = is_buy ? tick.bid : tick.ask;
      double favorable_distance = is_buy ? current_price - open_price : open_price - current_price;
      if(InpUseBreakEven && initial_risk > 0.0 && favorable_distance >= initial_risk * InpBreakEvenAtR)
      {
         if((is_buy && open_price > new_sl) || (!is_buy && open_price < new_sl))
            new_sl = open_price;
      }
      if(InpUseATRTrailing)
      {
         int atr_handle = iATR(symbol, InpTimeframe, 14);
         if(atr_handle != INVALID_HANDLE)
         {
            double atr[];
            ArraySetAsSeries(atr, true);
            if(CopyBuffer(atr_handle, 0, 1, 1, atr) == 1 && atr[0] > 0.0)
            {
               double trailing_sl = is_buy ? tick.bid - atr[0] * InpTrailingATRMultiple
                                            : tick.ask + atr[0] * InpTrailingATRMultiple;
               if((is_buy && trailing_sl > new_sl) || (!is_buy && trailing_sl < new_sl))
                  new_sl = trailing_sl;
            }
            IndicatorRelease(atr_handle);
         }
      }
      if(new_sl == current_sl)
         continue;

      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double minimum_distance = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
      new_sl = NormalizeDouble(new_sl, digits);
      bool valid_distance = is_buy ? (tick.bid - new_sl >= minimum_distance && new_sl < tick.bid)
                                   : (new_sl - tick.ask >= minimum_distance && new_sl > tick.ask);
      if(valid_distance && !g_trade.PositionModify(ticket, new_sl, current_tp))
         g_last_error = "Protection modification failed: " + g_trade.ResultRetcodeDescription();
   }
}

void GFScan()
{
   if(!g_running)
      return;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   {
      g_status = "CONNECTION ERROR - MT5 DISCONNECTED OR TRADING DISABLED";
      return;
   }
   if(GFDailyLossProtectionActive(InpMagicNumber, g_max_daily_loss_percent))
   {
      g_status = "RISK PROTECTION ACTIVE";
      if(InpClosePositionsOnDailyLoss)
         GFCloseManagedPositions(false);
      return;
   }
   g_status = "ANALYZING MARKET";
   if(g_consecutive_losses >= InpMaximumConsecutiveLosses ||
      (g_last_loss_time > 0 && TimeTradeServer() - g_last_loss_time < InpLossCooldownMinutes * 60))
   {
      g_status = "RISK PROTECTION ACTIVE - LOSS COOLDOWN";
      return;
   }
   if(!GFSessionAllowed())
   {
      g_status = "OUTSIDE TRADING SESSION";
      return;
   }
   if(InpUseNewsFilter)
   {
      g_status = "NEWS DATA SOURCE UNAVAILABLE - NEW ENTRIES BLOCKED";
      return;
   }
   if(GFCountDailyTrades(InpMagicNumber) >= g_daily_limit)
   {
      g_status = "DAILY TRADE LIMIT REACHED";
      return;
   }
   if(GFManagedPositionCount() >= g_max_open_positions)
   {
      g_status = "OPEN POSITION LIMIT REACHED";
      return;
   }

   GFOpportunity candidates[];
   if(GFBuildCandidates(candidates) == 0)
   {
      g_status = "RUNNING - WAITING FOR ENTRY";
      return;
   }
   int best = GFBestCandidate(candidates);
   if(best < 0)
      return;
   g_last_signal = (candidates[best].direction > 0 ? "BUY " : "SELL ") + candidates[best].symbol +
                   " score " + DoubleToString(candidates[best].score, 0);
   g_last_spread = candidates[best].spread;
   g_status = "VALID SIGNAL FOUND - VALIDATING RISK";
   if(!GFOpenCandidate(candidates[best]))
      g_status = "TRADE BLOCKED";
}

void GFCloseManagedPositions(const bool confirm_required)
{
   if(confirm_required && (!g_close_armed || TimeLocal() > g_close_confirm_until))
   {
      g_close_armed = true;
      g_close_confirm_until = TimeLocal() + 10;
      ObjectSetString(0, GFObject("Close"), OBJPROP_TEXT, "CONFIRM CLOSE (10s)");
      return;
   }
   g_close_armed = false;
   ObjectSetString(0, GFObject("Close"), OBJPROP_TEXT, "CLOSE EA POSITIONS");
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(ticket > 0 && PositionSelectByTicket(ticket) && GFIsManagedPosition())
      {
         if(!g_trade.PositionClose(ticket))
            g_last_error = "Close failed: " + g_trade.ResultRetcodeDescription();
      }
   }
}

int OnInit()
{
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
   {
      Print("GoldFirstBot is demo-only; initialization refused");
      return INIT_FAILED;
   }
   if(InpGoldTakeProfit <= 0.0 || InpGoldStopLoss <= 0.0 || InpDefaultRiskPercent <= 0.0 || InpDefaultRiskPercent > 5.0 ||
      InpMaximumGoldRiskPercent <= 0.0 || InpMaximumGoldRiskPercent > InpMaximumTotalRiskPercent ||
      InpMaximumTotalRiskPercent <= 0.0 || InpMaximumTotalRiskPercent > 100.0 ||
      InpMaximumDailyLossPercent <= 0.0 || InpMaximumDailyLossPercent > 10.0 ||
      InpDefaultMaximumOpenPositions < 1 || InpDefaultMaximumOpenPositions > 5 ||
      InpDefaultDailyTradeLimit < 1 || InpDefaultDailyTradeLimit > 50 ||
      InpDefaultMaximumPositionsPerSymbol != 1 || InpMaximumConsecutiveLosses < 1 ||
      InpMaximumHoldHours < 0 || InpBreakEvenAtR <= 0.0 || InpTrailingATRMultiple <= 0.0 ||
      InpSessionStartHour < 0 || InpSessionStartHour > 23 || InpSessionEndHour < 0 || InpSessionEndHour > 23 ||
      InpMinimumFreeMarginPercent < 0.0 || InpMinimumFreeMarginPercent > 100.0 ||
      InpForexTakeProfitATR <= 0.0 || InpForexStopLossATR <= 0.0 ||
      InpMinimumRewardRisk <= 0.0 || InpDefaultMinimumSetupScore < 0.0 || InpDefaultMinimumSetupScore > 100.0 ||
      InpMaximumGoldSpread <= 0.0 || InpMaximumForexSpread <= 0.0 || InpMaximumGoldATR <= 0.0 || InpMaximumForexATR <= 0.0)
      return INIT_PARAMETERS_INCORRECT;

   g_trade.SetExpertMagicNumber((ulong)InpMagicNumber);
   g_trade.SetDeviationInPoints(30);
   g_daily_limit = InpDefaultDailyTradeLimit;
   g_max_open_positions = InpDefaultMaximumOpenPositions;
   g_max_positions_per_symbol = InpDefaultMaximumPositionsPerSymbol;
   g_risk_percent = InpDefaultRiskPercent;
   g_max_daily_loss_percent = InpMaximumDailyLossPercent;
   g_minimum_score = InpDefaultMinimumSetupScore;
   g_gold_enabled = InpEnableGold;
   g_eurusd_enabled = InpEnableEURUSD;
   g_extras_enabled = InpEnableAdditionalSymbols;
   GFInitializeSymbols();
   if(ArraySize(g_symbols) == 0)
      return INIT_PARAMETERS_INCORRECT;

   string auto_key = GFStateKey("auto_start");
   if(!GlobalVariableCheck(auto_key))
      GlobalVariableSet(auto_key, InpAutoStartDefault ? 1.0 : 0.0);
   g_auto_start = GlobalVariableGet(auto_key) > 0.5;
   string was_running_key = GFStateKey("was_running");
   g_running = g_auto_start && GlobalVariableCheck(was_running_key) && GlobalVariableGet(was_running_key) > 0.5;
   if(GlobalVariableCheck(GFStateKey("daily_limit")))
      g_daily_limit = (int)GlobalVariableGet(GFStateKey("daily_limit"));
   if(GlobalVariableCheck(GFStateKey("max_positions")))
      g_max_open_positions = (int)GlobalVariableGet(GFStateKey("max_positions"));
   if(GlobalVariableCheck(GFStateKey("risk_percent")))
      g_risk_percent = GlobalVariableGet(GFStateKey("risk_percent"));
   if(GlobalVariableCheck(GFStateKey("daily_loss")))
      g_max_daily_loss_percent = GlobalVariableGet(GFStateKey("daily_loss"));
   if(GlobalVariableCheck(GFStateKey("minimum_score")))
      g_minimum_score = GlobalVariableGet(GFStateKey("minimum_score"));
   if(g_daily_limit < 1 || g_daily_limit > 50)
      g_daily_limit = InpDefaultDailyTradeLimit;
   if(g_max_open_positions < 1 || g_max_open_positions > 5)
      g_max_open_positions = InpDefaultMaximumOpenPositions;
   if(g_risk_percent <= 0.0 || g_risk_percent > 5.0)
      g_risk_percent = InpDefaultRiskPercent;
   if(g_max_daily_loss_percent <= 0.0 || g_max_daily_loss_percent > 10.0)
      g_max_daily_loss_percent = InpMaximumDailyLossPercent;
   if(g_minimum_score < 0.0 || g_minimum_score > 100.0)
      g_minimum_score = InpDefaultMinimumSetupScore;
   if(GlobalVariableCheck(GFStateKey("consecutive_losses")))
      g_consecutive_losses = (int)GlobalVariableGet(GFStateKey("consecutive_losses"));
   if(GlobalVariableCheck(GFStateKey("last_loss_time")))
      g_last_loss_time = (datetime)GlobalVariableGet(GFStateKey("last_loss_time"));

   GFDayStartingEquity(InpMagicNumber);
   GFBuildDashboard();
   EventSetTimer(1);
   g_status = g_running ? "RUNNING - WAITING FOR ENTRY" : "STOPPED - PRESS START";
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   GlobalVariableSet(GFStateKey("was_running"), g_running ? 1.0 : 0.0);
   GlobalVariablesFlush();
   EventKillTimer();
   ObjectsDeleteAll(0, g_prefix);
   ChartRedraw();
}

void OnTimer()
{
   datetime now = TimeTradeServer();
   GFProcessDashboardCommand();
   GFManageOpenPositions();
   if(now - g_last_scan_time >= InpScanIntervalSeconds)
   {
      g_last_scan_time = now;
      GFScan();
   }
   if(now - g_last_history_time >= 15)
   {
      g_last_history_time = now;
      g_daily_entries = GFCountDailyTrades(InpMagicNumber);
      GFCountClosedTradesToday(InpMagicNumber, g_wins_today, g_losses_today);
      g_closed_today = GFClosedProfitToday();
      g_floating = GFManagedFloating();
      g_open_risk = GFOpenRiskMoney(InpMagicNumber);
   }
   if(now - g_last_dashboard_time >= 1)
   {
      g_last_dashboard_time = now;
      GFRefreshDashboard();
      GFWriteStatusFile();
   }
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;
   if(sparam == GFObject("Start"))
   {
      if(GFValidateDashboard())
      {
         if(GFDailyLossProtectionActive(InpMagicNumber, g_max_daily_loss_percent))
            g_status = "PROTECTION ACTIVE - START REFUSED";
         else
         {
            g_running = true;
            g_status = "RUNNING - WAITING FOR ENTRY";
            GlobalVariableSet(GFStateKey("was_running"), 1.0);
         }
      }
   }
   else if(sparam == GFObject("Stop"))
   {
      g_running = false;
      g_status = "STOPPED - EXISTING STOPS ACTIVE";
      GlobalVariableSet(GFStateKey("was_running"), 0.0);
   }
   else if(sparam == GFObject("Auto"))
   {
      g_auto_start = !g_auto_start;
      GlobalVariableSet(GFStateKey("auto_start"), g_auto_start ? 1.0 : 0.0);
      if(!g_auto_start)
         GlobalVariableSet(GFStateKey("was_running"), 0.0);
      GFSyncControls();
   }
   else if(sparam == GFObject("Close"))
      GFCloseManagedPositions(true);
   else if(sparam == GFObject("Gold"))
   {
      g_gold_enabled = !g_gold_enabled;
      GFInitializeSymbols();
      GFSyncControls();
   }
   else if(sparam == GFObject("EUR"))
   {
      g_eurusd_enabled = !g_eurusd_enabled;
      GFInitializeSymbols();
      GFSyncControls();
   }
   else if(sparam == GFObject("Extras"))
   {
      g_extras_enabled = !g_extras_enabled;
      GFInitializeSymbols();
      GFSyncControls();
   }
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   ChartRedraw();
}

void OnTradeTransaction(const MqlTradeTransaction &transaction, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(transaction.type != TRADE_TRANSACTION_DEAL_ADD || transaction.deal == 0 || !HistoryDealSelect(transaction.deal))
      return;
   if(HistoryDealGetInteger(transaction.deal, DEAL_MAGIC) != InpMagicNumber)
      return;
   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(transaction.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT)
   {
      string symbol = HistoryDealGetString(transaction.deal, DEAL_SYMBOL);
      ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(transaction.deal, DEAL_TYPE);
      string direction = deal_type == DEAL_TYPE_BUY ? "BUY" : "SELL";
      double fill_price = HistoryDealGetDouble(transaction.deal, DEAL_PRICE);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      g_status = "TRADE EXECUTED";
      g_last_trade = "EXECUTED " + direction + " " + symbol + " @ " + DoubleToString(fill_price, digits);
      return;
   }
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;
   ulong position_id = (ulong)HistoryDealGetInteger(transaction.deal, DEAL_POSITION_ID);
   string closed_key = GFStateKey("closed_" + (string)position_id);
   if(GlobalVariableCheck(closed_key))
      return;
   if(GFPositionIdentifierOpen(position_id))
      return;
   if(!HistorySelectByPosition(position_id))
      return;
   double net = 0.0;
   double volume = 0.0;
   string symbol = "";
   string direction = "";
   for(int index = 0; index < HistoryDealsTotal(); index++)
   {
      ulong deal = HistoryDealGetTicket(index);
      if(deal == 0 || HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber)
         continue;
      net += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) +
             HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
      ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(deal_entry == DEAL_ENTRY_IN || deal_entry == DEAL_ENTRY_INOUT)
      {
         volume += HistoryDealGetDouble(deal, DEAL_VOLUME);
         symbol = HistoryDealGetString(deal, DEAL_SYMBOL);
         ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);
         direction = deal_type == DEAL_TYPE_BUY ? "BUY" : "SELL";
      }
   }
   if(net < 0.0)
   {
      g_consecutive_losses++;
      g_last_loss_time = TimeTradeServer();
   }
   else
      g_consecutive_losses = 0;
   GlobalVariableSet(GFStateKey("consecutive_losses"), g_consecutive_losses);
   GlobalVariableSet(GFStateKey("last_loss_time"), (double)g_last_loss_time);
   GlobalVariableSet(closed_key, 1.0);
   GlobalVariablesFlush();
   GFLogClosedPosition(position_id, symbol, direction, volume, net);
   g_last_trade = symbol + " " + direction + " closed " + (net >= 0.0 ? "+" : "") + DoubleToString(net, 2);
   g_status = "TRADE CLOSED";
}