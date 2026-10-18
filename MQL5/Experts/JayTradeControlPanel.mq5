#property strict
#property version   "1.00"
#property description "JayTrade MT5 control panel with TradingView alerts and broker-side risk limits"

#include <Trade/Trade.mqh>

input string InpSymbol = "XAUUSD";
input double InpLots = 0.02;
input double InpTakeProfitUSD = 10.0;
input double InpStopLossUSD = 3.0;
input int InpMaxPositions = 20;
input int InpEntryIntervalSeconds = 60;
input int InpDefaultRunMinutes = 60;
input long InpMagic = 801016;
input string InpSignalUrl = "http://127.0.0.1:5001/signals/latest";
input string InpSignalToken = "";

CTrade g_trade;
bool g_running = false;
bool g_session_has_limit = true;
ulong g_run_ends_at = 0;
ulong g_next_entry_at = 0;
long g_last_signal_sequence = 0;
string g_status = "STOPPED";
string g_prefix = "JayTradePanel_";

color COLOR_BG = C'17,25,34';
color COLOR_PANEL = C'24,35,47';
color COLOR_EDGE = C'46,66,78';
color COLOR_TEXT = C'226,235,239';
color COLOR_MUTED = C'145,163,172';
color COLOR_TEAL = C'35,195,170';
color COLOR_RED = C'221,91,91';
color COLOR_BLUE = C'70,145,205';

string ObjectName(const string suffix)
{
   return g_prefix + suffix;
}

bool CreateRect(const string suffix, int x, int y, int width, int height, color fill, color border)
{
   string name = ObjectName(suffix);
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
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   return true;
}

bool CreateLabel(const string suffix, const string text, int x, int y, int size, color text_color)
{
   string name = ObjectName(suffix);
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

bool CreateButton(const string suffix, const string text, int x, int y, int width, int height, color fill)
{
   string name = ObjectName(suffix);
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
      return false;
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, fill);
   ObjectSetInteger(0, name, OBJPROP_COLOR, COLOR_TEXT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, fill);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   return true;
}

bool CreateEdit(const string suffix, const string text, int x, int y, int width, int height)
{
   string name = ObjectName(suffix);
   if(!ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0))
      return false;
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, COLOR_BG);
   ObjectSetInteger(0, name, OBJPROP_COLOR, COLOR_TEXT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, COLOR_EDGE);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   return true;
}

void CreatePanel()
{
   CreateRect("Background", 18, 22, 338, 302, COLOR_PANEL, COLOR_EDGE);
   CreateRect("Accent", 18, 22, 4, 302, COLOR_TEAL, COLOR_TEAL);
   CreateLabel("Title", "JAYTRADE  /  CONTROL", 36, 38, 12, COLOR_TEXT);
   CreateLabel("Subtitle", "TradingView signal execution", 36, 60, 9, COLOR_MUTED);
   CreateLabel("StatusCaption", "STATUS", 36, 88, 8, COLOR_MUTED);
   CreateLabel("Status", "STOPPED", 36, 104, 12, COLOR_RED);
   CreateLabel("SymbolCaption", "INSTRUMENT", 36, 137, 8, COLOR_MUTED);
   CreateLabel("Symbol", InpSymbol + "  /  " + DoubleToString(InpLots, 2) + " lot", 36, 153, 10, COLOR_TEXT);
   CreateLabel("Risk", "+$" + DoubleToString(InpTakeProfitUSD, 2) + " target     -$" + DoubleToString(InpStopLossUSD, 2) + " stop", 36, 177, 9, COLOR_TEXT);
   CreateLabel("DurationCaption", "SESSION MINUTES", 36, 207, 8, COLOR_MUTED);
   CreateEdit("Duration", IntegerToString(InpDefaultRunMinutes), 158, 199, 58, 24);
   CreateLabel("DurationHint", "0 = no limit", 226, 205, 8, COLOR_MUTED);
   CreateButton("Start", "START", 36, 239, 124, 32, COLOR_TEAL);
   CreateButton("Stop", "STOP", 170, 239, 124, 32, COLOR_RED);
   CreateButton("Buy", "BUY", 36, 280, 124, 30, COLOR_BLUE);
   CreateButton("Sell", "SELL", 170, 280, 124, 30, COLOR_BLUE);
   CreateLabel("Footer", "MAX " + IntegerToString(InpMaxPositions) + "  /  1 entry per " + IntegerToString(InpEntryIntervalSeconds) + " sec", 36, 319, 8, COLOR_MUTED);
   ChartRedraw();
}

void SetStatus(const string text, color status_color)
{
   g_status = text;
   ObjectSetString(0, ObjectName("Status"), OBJPROP_TEXT, text);
   ObjectSetInteger(0, ObjectName("Status"), OBJPROP_COLOR, status_color);
   ChartRedraw();
}

bool FindPriceForProfit(const string symbol, bool is_buy, double volume, double open_price, double target, double &result_price)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(point <= 0.0)
      return false;
   if(tick_size <= 0.0)
      tick_size = point;

   ENUM_ORDER_TYPE order_type = is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   int price_direction = ((is_buy && target > 0.0) || (!is_buy && target < 0.0)) ? 1 : -1;
   double step = MathMax(tick_size, MathAbs(open_price) * 0.000001);
   double tolerance = MathMax(0.000001, MathAbs(target) * 0.0000000001);
   double inside = open_price;
   double outside = 0.0;
   bool bracket_found = false;

   for(int attempt = 0; attempt < 48; attempt++)
   {
      double candidate = NormalizeDouble(open_price + price_direction * step, digits);
      if(candidate <= 0.0)
         return false;
      double profit = 0.0;
      if(!OrderCalcProfit(order_type, symbol, volume, open_price, candidate, profit))
         return false;
      bool reached = target > 0.0 ? profit >= target - tolerance : profit <= target + tolerance;
      if(reached)
      {
         outside = candidate;
         bracket_found = true;
         break;
      }
      step *= 2.0;
   }
   if(!bracket_found)
      return false;

   for(int attempt = 0; attempt < 48; attempt++)
   {
      double midpoint = NormalizeDouble((inside + outside) / 2.0, digits);
      if(midpoint == inside || midpoint == outside)
         break;
      double profit = 0.0;
      if(!OrderCalcProfit(order_type, symbol, volume, open_price, midpoint, profit))
         return false;
      bool reached = target > 0.0 ? profit >= target - tolerance : profit <= target + tolerance;
      if(reached)
         outside = midpoint;
      else
         inside = midpoint;
   }

   double ticks = outside / tick_size;
   result_price = NormalizeDouble(
      (price_direction > 0 ? MathCeil(ticks - 1e-10) : MathFloor(ticks + 1e-10)) * tick_size,
      digits
   );
   for(int attempt = 0; attempt < 100; attempt++)
   {
      double profit = 0.0;
      if(!OrderCalcProfit(order_type, symbol, volume, open_price, result_price, profit))
         return false;
      bool reached = target > 0.0 ? profit >= target - tolerance : profit <= target + tolerance;
      if(reached)
         return true;
      result_price = NormalizeDouble(result_price + price_direction * tick_size, digits);
   }
   return false;
}

int ManagedPositionCount()
{
   int count = 0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(IsManagedPosition())
         count++;
   }
   return count;
}

bool IsManagedPosition()
{
   long magic = PositionGetInteger(POSITION_MAGIC);
   string comment = PositionGetString(POSITION_COMMENT);
   return magic == InpMagic ||
      StringFind(comment, "jaytrade") == 0 ||
      StringFind(comment, "JayTrade") == 0;
}

void ManagePositions()
{
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsManagedPosition())
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      bool is_buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double volume = PositionGetDouble(POSITION_VOLUME);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(current_profit >= InpTakeProfitUSD || current_profit <= -InpStopLossUSD)
      {
         if(g_trade.PositionClose(ticket))
            Print("JayTrade closed ticket ", ticket, " at floating P/L ", DoubleToString(current_profit, 2));
         else
            Print("JayTrade close retry required for ticket ", ticket, ": ", g_trade.ResultRetcodeDescription());
         continue;
      }

      double take_profit = 0.0;
      double stop_loss = 0.0;
      if(!FindPriceForProfit(symbol, is_buy, volume, open_price, InpTakeProfitUSD, take_profit) ||
         !FindPriceForProfit(symbol, is_buy, volume, open_price, -InpStopLossUSD, stop_loss))
      {
         Print("Could not calculate protective prices for ticket ", ticket);
         continue;
      }

      double current_tp = PositionGetDouble(POSITION_TP);
      double current_sl = PositionGetDouble(POSITION_SL);
      double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tick_size <= 0.0)
         tick_size = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(MathAbs(current_tp - take_profit) > tick_size / 2.0 || MathAbs(current_sl - stop_loss) > tick_size / 2.0)
      {
         if(!g_trade.PositionModify(ticket, stop_loss, take_profit))
            Print("Could not update protection for ticket ", ticket, ": ", g_trade.ResultRetcodeDescription());
      }
   }
}

long JsonLong(const string json, const string key)
{
   string marker = "\"" + key + "\"";
   int position = StringFind(json, marker);
   if(position < 0)
      return 0;
   position = StringFind(json, ":", position + StringLen(marker));
   if(position < 0)
      return 0;
   position++;
   while(position < StringLen(json) && (StringGetCharacter(json, position) == ' ' || StringGetCharacter(json, position) == '\t'))
      position++;
   int end = position;
   while(end < StringLen(json) && StringGetCharacter(json, end) >= '0' && StringGetCharacter(json, end) <= '9')
      end++;
   return StringToInteger(StringSubstr(json, position, end - position));
}

string JsonString(const string json, const string key)
{
   string marker = "\"" + key + "\"";
   int position = StringFind(json, marker);
   if(position < 0)
      return "";
   position = StringFind(json, ":", position + StringLen(marker));
   if(position < 0)
      return "";
   position++;
   while(position < StringLen(json) && (StringGetCharacter(json, position) == ' ' || StringGetCharacter(json, position) == '\t'))
      position++;
   if(position >= StringLen(json) || StringGetCharacter(json, position) != '"')
      return "";
   int end = StringFind(json, "\"", position + 1);
   if(end < 0)
      return "";
   return StringSubstr(json, position + 1, end - position - 1);
}

bool FetchLatestSignal(long &sequence, string &symbol, string &action)
{
   if(StringLen(InpSignalToken) == 0)
      return false;
   string headers = "X-Signal-Token: " + InpSignalToken + "\r\n";
   char request_data[];
   char response_data[];
   string response_headers;
   ArrayResize(request_data, 0);
   ResetLastError();
   int response_code = WebRequest("GET", InpSignalUrl, headers, 2000, request_data, response_data, response_headers);
   if(response_code != 200)
   {
      if(response_code == -1)
         SetStatus("ALLOW LOCAL URL IN MT5", COLOR_RED);
      return false;
   }
   string body = CharArrayToString(response_data, 0, -1, CP_UTF8);
   sequence = JsonLong(body, "sequence");
   symbol = JsonString(body, "symbol");
   action = JsonString(body, "action");
   StringToUpper(action);
   return sequence > 0 && StringLen(symbol) > 0 && (action == "BUY" || action == "SELL");
}

bool SignalMatchesChart(string signal_symbol)
{
   int colon = StringFind(signal_symbol, ":");
   if(colon >= 0)
      signal_symbol = StringSubstr(signal_symbol, colon + 1);
   StringToUpper(signal_symbol);
   string configured_symbol = InpSymbol;
   StringToUpper(configured_symbol);
   return signal_symbol == configured_symbol;
}

bool OpenPosition(const string direction, const string source)
{
   if(!g_running)
   {
      SetStatus("START SESSION FIRST", COLOR_RED);
      return false;
   }
   if(g_session_has_limit && GetTickCount64() >= g_run_ends_at)
   {
      g_running = false;
      SetStatus("SESSION TIME ENDED", COLOR_RED);
      return false;
   }
   if(GetTickCount64() < g_next_entry_at)
   {
      SetStatus("ENTRY COOLDOWN ACTIVE", COLOR_MUTED);
      return false;
   }
   if(ManagedPositionCount() >= InpMaxPositions)
   {
      SetStatus("MAX POSITIONS OPEN", COLOR_RED);
      return false;
   }

   string symbol = InpSymbol;
   if(!SymbolSelect(symbol, true))
   {
      SetStatus("SYMBOL NOT AVAILABLE", COLOR_RED);
      return false;
   }
   bool is_buy = direction == "BUY";
   double entry_price = SymbolInfoDouble(symbol, is_buy ? SYMBOL_ASK : SYMBOL_BID);
   double take_profit = 0.0;
   double stop_loss = 0.0;
   if(entry_price <= 0.0 ||
      !FindPriceForProfit(symbol, is_buy, InpLots, entry_price, InpTakeProfitUSD, take_profit) ||
      !FindPriceForProfit(symbol, is_buy, InpLots, entry_price, -InpStopLossUSD, stop_loss))
   {
      SetStatus("RISK PRICE CALCULATION FAILED", COLOR_RED);
      return false;
   }

   bool sent = is_buy
      ? g_trade.Buy(InpLots, symbol, entry_price, stop_loss, take_profit, "JayTrade TV signal")
      : g_trade.Sell(InpLots, symbol, entry_price, stop_loss, take_profit, "JayTrade TV signal");
   uint retcode = g_trade.ResultRetcode();
   if(!sent || (retcode != TRADE_RETCODE_DONE && retcode != TRADE_RETCODE_PLACED))
   {
      Print("JayTrade order rejected: ", g_trade.ResultRetcodeDescription());
      SetStatus("ORDER REJECTED - SEE JOURNAL", COLOR_RED);
      return false;
   }

   g_next_entry_at = GetTickCount64() + (ulong)InpEntryIntervalSeconds * 1000;
   SetStatus(direction + " OPENED / " + source, COLOR_TEAL);
   Print("JayTrade opened ", direction, " ", symbol, " ticket ", g_trade.ResultOrder(),
         " TP=$", DoubleToString(InpTakeProfitUSD, 2), " SL=$", DoubleToString(InpStopLossUSD, 2));
   return true;
}

void PrimeSignalSequence()
{
   long sequence = 0;
   string symbol = "";
   string action = "";
   if(FetchLatestSignal(sequence, symbol, action))
      g_last_signal_sequence = sequence;
}

void StartSession()
{
   string duration_text = ObjectGetString(0, ObjectName("Duration"), OBJPROP_TEXT);
   int duration_minutes = (int)StringToInteger(duration_text);
   if(duration_minutes < 0)
   {
      SetStatus("DURATION MUST BE 0 OR MORE", COLOR_RED);
      return;
   }
   g_running = true;
   g_session_has_limit = duration_minutes > 0;
   g_run_ends_at = g_session_has_limit ? GetTickCount64() + (ulong)duration_minutes * 60000 : 0;
   g_next_entry_at = GetTickCount64();
   PrimeSignalSequence();
   SetStatus(g_session_has_limit ? "RUNNING / TIME LIMITED" : "RUNNING / NO TIME LIMIT", COLOR_TEAL);
}

void StopSession()
{
   g_running = false;
   SetStatus("STOPPED / OPEN TRADES PROTECTED", COLOR_MUTED);
}

int OnInit()
{
   if(InpLots <= 0.0 || InpTakeProfitUSD <= 0.0 || InpStopLossUSD <= 0.0 ||
   InpLots != 0.02 || InpTakeProfitUSD != 10.0 || InpStopLossUSD != 3.0 ||
   InpMaxPositions < 1 || InpMaxPositions > 20 || InpEntryIntervalSeconds < 60)
      return INIT_PARAMETERS_INCORRECT;
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
   {
      Print("JayTrade Control Panel only runs on an MT5 demo account");
      return INIT_FAILED;
   }
   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints(30);
   CreatePanel();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, g_prefix);
   ChartRedraw();
}

void OnTimer()
{
   ManagePositions();
   if(!g_running)
      return;
   if(g_session_has_limit && GetTickCount64() >= g_run_ends_at)
   {
      g_running = false;
      SetStatus("SESSION ENDED / TRADES PROTECTED", COLOR_MUTED);
      return;
   }
   if(GetTickCount64() < g_next_entry_at || ManagedPositionCount() >= InpMaxPositions)
      return;

   long sequence = 0;
   string symbol = "";
   string action = "";
   if(!FetchLatestSignal(sequence, symbol, action))
   {
      if(StringLen(InpSignalToken) == 0)
         SetStatus("MANUAL MODE / ADD SIGNAL TOKEN", COLOR_MUTED);
      return;
   }
   if(sequence <= g_last_signal_sequence)
      return;
   g_last_signal_sequence = sequence;
   if(!SignalMatchesChart(symbol))
   {
      SetStatus("IGNORED SIGNAL FOR " + symbol, COLOR_MUTED);
      return;
   }
   OpenPosition(action, "TRADINGVIEW");
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;
   if(sparam == ObjectName("Start"))
   {
      StartSession();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   else if(sparam == ObjectName("Stop"))
   {
      StopSession();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   else if(sparam == ObjectName("Buy"))
   {
      OpenPosition("BUY", "MANUAL");
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   else if(sparam == ObjectName("Sell"))
   {
      OpenPosition("SELL", "MANUAL");
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   ChartRedraw();
}