#ifndef GOLD_FIRST_RISK_MQH
#define GOLD_FIRST_RISK_MQH

string GFDayKey(const long magic, const string suffix)
{
   MqlDateTime broker_time;
   TimeToStruct(TimeTradeServer(), broker_time);
   string day = StringFormat("%04d%02d%02d", broker_time.year, broker_time.mon, broker_time.day);
   return "GFR" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" +
          IntegerToString((int)magic) + "_" + day + "_" + suffix;
}

datetime GFBrokerDayStart()
{
   MqlDateTime broker_time;
   TimeToStruct(TimeTradeServer(), broker_time);
   broker_time.hour = 0;
   broker_time.min = 0;
   broker_time.sec = 0;
   return StructToTime(broker_time);
}

bool GFPositionIdentifierOpen(const ulong position_id)
{
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == position_id)
         return true;
   }
   return false;
}

double GFDayStartingEquity(const long magic)
{
   string key = GFDayKey(magic, "equity");
   if(!GlobalVariableCheck(key))
   {
      GlobalVariableSet(key, AccountInfoDouble(ACCOUNT_EQUITY));
      GlobalVariablesFlush();
   }
   return GlobalVariableGet(key);
}

bool GFDailyLossProtectionActive(const long magic, const double daily_loss_percent)
{
   string halt_key = GFDayKey(magic, "halt");
   if(GlobalVariableCheck(halt_key) && GlobalVariableGet(halt_key) > 0.5)
      return true;
   double start_equity = GFDayStartingEquity(magic);
   if(start_equity <= 0.0)
      return true;
   double loss_percent = (start_equity - AccountInfoDouble(ACCOUNT_EQUITY)) / start_equity * 100.0;
   if(loss_percent >= daily_loss_percent)
   {
      GlobalVariableSet(halt_key, 1.0);
      GlobalVariablesFlush();
      return true;
   }
   return false;
}

int GFCountDailyTrades(const long magic)
{
   datetime now = TimeTradeServer();
   datetime day_start = GFBrokerDayStart();
   if(!HistorySelect(day_start, now))
      return 0;

   ulong position_ids[];
   int unique_count = 0;
   int total = HistoryDealsTotal();
   for(int index = 0; index < total; index++)
   {
      ulong deal = HistoryDealGetTicket(index);
      if(deal == 0 || HistoryDealGetInteger(deal, DEAL_MAGIC) != magic)
         continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT)
         continue;
      ulong position_id = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      bool already_counted = false;
      for(int item = 0; item < unique_count; item++)
      {
         if(position_ids[item] == position_id)
         {
            already_counted = true;
            break;
         }
      }
      if(!already_counted)
      {
         ArrayResize(position_ids, unique_count + 1);
         position_ids[unique_count++] = position_id;
      }
   }

   GlobalVariableSet(GFDayKey(magic, "trades"), unique_count);
   GlobalVariablesFlush();
   return unique_count;
}

void GFCountClosedTradesToday(const long magic, int &wins, int &losses)
{
   wins = 0;
   losses = 0;
   if(!HistorySelect(GFBrokerDayStart(), TimeTradeServer()))
      return;

   ulong closed_ids[];
   int unique_count = 0;
   int total = HistoryDealsTotal();
   for(int index = 0; index < total; index++)
   {
      ulong deal = HistoryDealGetTicket(index);
      if(deal == 0 || HistoryDealGetInteger(deal, DEAL_MAGIC) != magic)
         continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
         continue;
      ulong position_id = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      bool seen = false;
      for(int item = 0; item < unique_count; item++)
      {
         if(closed_ids[item] == position_id)
         {
            seen = true;
            break;
         }
      }
      if(!seen)
      {
         ArrayResize(closed_ids, unique_count + 1);
         closed_ids[unique_count++] = position_id;
      }
   }

   for(int item = 0; item < unique_count; item++)
   {
      ulong position_id = closed_ids[item];
      if(GFPositionIdentifierOpen(position_id) || !HistorySelectByPosition(position_id))
         continue;
      double net = 0.0;
      for(int index = 0; index < HistoryDealsTotal(); index++)
      {
         ulong deal = HistoryDealGetTicket(index);
         if(deal != 0 && HistoryDealGetInteger(deal, DEAL_MAGIC) == magic)
            net += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) +
                   HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
      }
      if(net > 0.0)
         wins++;
      else if(net < 0.0)
         losses++;
   }
}

double GFRiskForPosition(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return 0.0;
   string symbol = PositionGetString(POSITION_SYMBOL);
   double stop = PositionGetDouble(POSITION_SL);
   if(stop <= 0.0)
      return 1.0e100;
   ENUM_ORDER_TYPE side = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double profit = 0.0;
   if(!OrderCalcProfit(side, symbol, PositionGetDouble(POSITION_VOLUME), PositionGetDouble(POSITION_PRICE_OPEN), stop, profit))
      return 1.0e100;
   return MathMax(0.0, -profit);
}

bool GFIsBuyPending(const ENUM_ORDER_TYPE type)
{
   return type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT;
}

double GFRiskForPendingOrder(const ulong ticket)
{
   if(!OrderSelect(ticket))
      return 0.0;
   string symbol = OrderGetString(ORDER_SYMBOL);
   double stop = OrderGetDouble(ORDER_SL);
   if(stop <= 0.0)
      return 1.0e100;
   ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   ENUM_ORDER_TYPE side = GFIsBuyPending(type) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double profit = 0.0;
   if(!OrderCalcProfit(side, symbol, OrderGetDouble(ORDER_VOLUME_CURRENT), OrderGetDouble(ORDER_PRICE_OPEN), stop, profit))
      return 1.0e100;
   return MathMax(0.0, -profit);
}

double GFOpenRiskMoney(const long magic)
{
   double total_risk = 0.0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(ticket > 0 && PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == magic)
         total_risk += GFRiskForPosition(ticket);
   }
   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      ulong ticket = OrderGetTicket(index);
      if(ticket > 0 && OrderGetInteger(ORDER_MAGIC) == magic)
         total_risk += GFRiskForPendingOrder(ticket);
   }
   return total_risk;
}

bool GFCalculateVolume(
   const string symbol,
   const int direction,
   const double entry,
   const double stop_loss,
   const long magic,
   const double risk_percent,
   const double maximum_total_risk_percent,
   const double minimum_free_margin_percent,
   double &volume,
   double &risk_money)
{
   volume = 0.0;
   risk_money = 0.0;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0 || risk_percent <= 0.0 || maximum_total_risk_percent <= 0.0)
      return false;

   double total_risk_limit = equity * maximum_total_risk_percent / 100.0;
   double available_risk = total_risk_limit - GFOpenRiskMoney(magic);
   risk_money = MathMin(equity * risk_percent / 100.0, available_risk);
   if(risk_money <= 0.0)
      return false;

   ENUM_ORDER_TYPE side = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double loss_per_lot = 0.0;
   if(!OrderCalcProfit(side, symbol, 1.0, entry, stop_loss, loss_per_lot) || loss_per_lot >= 0.0)
      return false;
   loss_per_lot = MathAbs(loss_per_lot);

   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minimum = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maximum = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0 || minimum <= 0.0 || maximum <= 0.0)
      return false;
   volume = MathMin(maximum, MathFloor((risk_money / loss_per_lot) / step) * step);
   volume = NormalizeDouble(volume, 8);
   if(volume < minimum || loss_per_lot * volume > risk_money + 0.01)
   {
      volume = 0.0;
      return false;
   }

   double margin = 0.0;
   if(!OrderCalcMargin(side, symbol, volume, entry, margin))
   {
      volume = 0.0;
      return false;
   }
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(free_margin <= margin || free_margin - margin < equity * minimum_free_margin_percent / 100.0)
   {
      volume = 0.0;
      return false;
   }
   risk_money = loss_per_lot * volume;
   return true;
}

#endif