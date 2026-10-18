#ifndef GOLD_FIRST_SIGNAL_MQH
#define GOLD_FIRST_SIGNAL_MQH

enum GFExitMode
{
   GF_EXIT_FIXED = 0,
   GF_EXIT_ATR = 1
};

struct GFOpportunity
{
   string symbol;
   int direction;
   double score;
   double atr;
   double spread;
   double entry;
   double stop_loss;
   double take_profit;
   double reward_risk;
   double rsi_value;
   double adx_value;
   bool direction_buy;
   bool direction_confirmed;
   bool market_data_available;
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
   bool score_applicable;
   bool score_acceptable;
   string reason;
};

bool GFBullishConfirmation(const MqlRates &current, const MqlRates &previous, const double point)
{
   double body = MathAbs(current.close - current.open);
   double lower_wick = MathMin(current.open, current.close) - current.low;
   bool engulfing = current.close > current.open && previous.close < previous.open &&
                    current.close >= previous.open && current.open <= previous.close;
   bool rejection = current.close > current.open && lower_wick >= MathMax(body * 1.5, point * 2.0) &&
                    current.close >= current.low + (current.high - current.low) * 0.65;
   return engulfing || rejection;
}

bool GFBearishConfirmation(const MqlRates &current, const MqlRates &previous, const double point)
{
   double body = MathAbs(current.close - current.open);
   double upper_wick = current.high - MathMax(current.open, current.close);
   bool engulfing = current.close < current.open && previous.close > previous.open &&
                    current.close <= previous.open && current.open >= previous.close;
   bool rejection = current.close < current.open && upper_wick >= MathMax(body * 1.5, point * 2.0) &&
                    current.close <= current.low + (current.high - current.low) * 0.35;
   return engulfing || rejection;
}

bool GFBuildOpportunity(
   const string symbol,
   const bool is_gold,
   const ENUM_TIMEFRAMES timeframe,
   const ENUM_TIMEFRAMES higher_timeframe,
   const int rsi_period,
   const int atr_period,
   const int adx_period,
   const bool use_adx,
   const double adx_minimum,
   const double rsi_buy_min,
   const double rsi_buy_max,
   const double rsi_sell_min,
   const double rsi_sell_max,
   const double pullback_atr_tolerance,
   const double maximum_spread,
   const double maximum_atr,
   const double gold_tp_distance,
   const double gold_sl_distance,
   const GFExitMode exit_mode,
   const double forex_tp_atr,
   const double forex_sl_atr,
   const double minimum_reward_risk,
   const double minimum_score,
   GFOpportunity &opportunity)
{
   opportunity.symbol = symbol;
   opportunity.direction = 0;
   opportunity.score = 0.0;
   opportunity.rsi_value = 0.0;
   opportunity.adx_value = 0.0;
   opportunity.direction_buy = true;
   opportunity.direction_confirmed = false;
   opportunity.market_data_available = false;
   opportunity.price_trend = false;
   opportunity.ema_stack = false;
   opportunity.higher_timeframe = false;
   opportunity.pullback = false;
   opportunity.rsi_confirmation = false;
   opportunity.candle_confirmation = false;
   opportunity.adx_confirmation = false;
   opportunity.spread_acceptable = false;
   opportunity.volatility_acceptable = false;
   opportunity.reward_risk_acceptable = false;
   opportunity.target_clearance_acceptable = false;
   opportunity.score_applicable = false;
   opportunity.score_acceptable = false;
   opportunity.reason = "No qualified setup";

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(symbol, timeframe, 1, 24, rates) < 24)
   {
      opportunity.reason = "Insufficient closed candles";
      return false;
   }

   int ema20_handle = iMA(symbol, timeframe, 20, 0, MODE_EMA, PRICE_CLOSE);
   int ema50_handle = iMA(symbol, timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
   int ema200_handle = iMA(symbol, timeframe, 200, 0, MODE_EMA, PRICE_CLOSE);
   int higher_ema_handle = iMA(symbol, higher_timeframe, 200, 0, MODE_EMA, PRICE_CLOSE);
   int rsi_handle = iRSI(symbol, timeframe, rsi_period, PRICE_CLOSE);
   int atr_handle = iATR(symbol, timeframe, atr_period);
   int adx_handle = use_adx ? iADX(symbol, timeframe, adx_period) : INVALID_HANDLE;
   if(ema20_handle == INVALID_HANDLE || ema50_handle == INVALID_HANDLE || ema200_handle == INVALID_HANDLE ||
      higher_ema_handle == INVALID_HANDLE ||
      rsi_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE || (use_adx && adx_handle == INVALID_HANDLE))
   {
      if(ema20_handle != INVALID_HANDLE) IndicatorRelease(ema20_handle);
      if(ema50_handle != INVALID_HANDLE) IndicatorRelease(ema50_handle);
      if(ema200_handle != INVALID_HANDLE) IndicatorRelease(ema200_handle);
      if(higher_ema_handle != INVALID_HANDLE) IndicatorRelease(higher_ema_handle);
      if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);
      if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
      if(adx_handle != INVALID_HANDLE) IndicatorRelease(adx_handle);
      opportunity.reason = "Indicator handle unavailable";
      return false;
   }

   double ema20[];
   double ema50[];
   double ema200[];
   double higher_ema[];
   double rsi[];
   double atr[];
   double adx[];
   ArraySetAsSeries(ema20, true);
   ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(ema200, true);
   ArraySetAsSeries(higher_ema, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(adx, true);
   bool copied = CopyBuffer(ema20_handle, 0, 1, 2, ema20) == 2 &&
                 CopyBuffer(ema50_handle, 0, 1, 2, ema50) == 2 &&
                 CopyBuffer(ema200_handle, 0, 1, 2, ema200) == 2 &&
                 CopyBuffer(higher_ema_handle, 0, 1, 1, higher_ema) == 1 &&
                 CopyBuffer(rsi_handle, 0, 1, 1, rsi) == 1 &&
                 CopyBuffer(atr_handle, 0, 1, 1, atr) == 1;
   if(copied && use_adx)
      copied = CopyBuffer(adx_handle, 0, 1, 1, adx) == 1;
   IndicatorRelease(ema20_handle);
   IndicatorRelease(ema50_handle);
   IndicatorRelease(ema200_handle);
   IndicatorRelease(higher_ema_handle);
   IndicatorRelease(rsi_handle);
   IndicatorRelease(atr_handle);
   if(adx_handle != INVALID_HANDLE)
      IndicatorRelease(adx_handle);
   if(!copied || atr[0] <= 0.0)
   {
      opportunity.reason = "Indicator data unavailable";
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
   {
      opportunity.reason = "No live quote";
      return false;
   }
   opportunity.market_data_available = true;
   if(tick.time <= 0 || TimeTradeServer() - tick.time > 60)
   {
      opportunity.reason = "Market quote is stale";
      return false;
   }
   double spread = tick.ask - tick.bid;
   opportunity.spread_acceptable = spread <= maximum_spread;
   opportunity.volatility_acceptable = atr[0] <= maximum_atr;
   opportunity.rsi_value = rsi[0];
   opportunity.adx_value = use_adx ? adx[0] : 0.0;
   if(spread > maximum_spread)
   {
      opportunity.reason = "Spread above symbol limit";
      return false;
   }
   if(atr[0] > maximum_atr)
   {
      opportunity.reason = "ATR above symbol limit";
      return false;
   }

   double support = rates[1].low;
   double resistance = rates[1].high;
   for(int index = 2; index < 22; index++)
   {
      support = MathMin(support, rates[index].low);
      resistance = MathMax(resistance, rates[index].high);
   }

   bool trend_buy = rates[0].close > ema200[0] && ema50[0] > ema200[0] && ema20[0] > ema50[0];
   bool trend_sell = rates[0].close < ema200[0] && ema50[0] < ema200[0] && ema20[0] < ema50[0];
   bool higher_buy = rates[0].close > higher_ema[0];
   bool higher_sell = rates[0].close < higher_ema[0];
   bool pullback_buy = rates[0].low <= ema20[0] + atr[0] * pullback_atr_tolerance ||
                       rates[0].low <= ema50[0] + atr[0] * pullback_atr_tolerance;
   bool pullback_sell = rates[0].high >= ema20[0] - atr[0] * pullback_atr_tolerance ||
                        rates[0].high >= ema50[0] - atr[0] * pullback_atr_tolerance;
   double symbol_point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   bool candle_buy = GFBullishConfirmation(rates[0], rates[1], symbol_point);
   bool candle_sell = GFBearishConfirmation(rates[0], rates[1], symbol_point);
   bool rsi_buy = rsi[0] >= rsi_buy_min && rsi[0] <= rsi_buy_max;
   bool rsi_sell = rsi[0] >= rsi_sell_min && rsi[0] <= rsi_sell_max;
   bool adx_ok = !use_adx || adx[0] >= adx_minimum;
   opportunity.direction_buy = rates[0].close >= ema200[0];
   opportunity.price_trend = opportunity.direction_buy ? rates[0].close > ema200[0] : rates[0].close < ema200[0];
   opportunity.ema_stack = opportunity.direction_buy
      ? ema50[0] > ema200[0] && ema20[0] > ema50[0]
      : ema50[0] < ema200[0] && ema20[0] < ema50[0];
   opportunity.higher_timeframe = opportunity.direction_buy ? higher_buy : higher_sell;
   opportunity.pullback = opportunity.direction_buy ? pullback_buy : pullback_sell;
   opportunity.rsi_confirmation = opportunity.direction_buy ? rsi_buy : rsi_sell;
   opportunity.candle_confirmation = opportunity.direction_buy ? candle_buy : candle_sell;
   opportunity.adx_confirmation = adx_ok;

   int direction = 0;
   if(trend_buy && pullback_buy && candle_buy && rsi_buy && adx_ok)
      direction = 1;
   else if(trend_sell && pullback_sell && candle_sell && rsi_sell && adx_ok)
      direction = -1;
   if(direction == 0)
   {
      opportunity.reason = "Trend/pullback/momentum confirmation incomplete";
      return false;
   }
   opportunity.direction_confirmed = true;

   double entry = direction > 0 ? tick.ask : tick.bid;
   double stop_distance = (is_gold && exit_mode == GF_EXIT_FIXED) ? gold_sl_distance : atr[0] * forex_sl_atr;
   double target_distance = (is_gold && exit_mode == GF_EXIT_FIXED) ? gold_tp_distance : atr[0] * forex_tp_atr;
   if(exit_mode == GF_EXIT_ATR)
   {
      stop_distance = atr[0] * forex_sl_atr;
      target_distance = atr[0] * forex_tp_atr;
   }
   if(stop_distance <= 0.0 || target_distance <= 0.0 || target_distance / stop_distance < minimum_reward_risk)
   {
      opportunity.reason = "Reward/risk below configured minimum";
      return false;
   }
   opportunity.reward_risk_acceptable = true;
   double stop_loss = entry - direction * stop_distance;
   double take_profit = entry + direction * target_distance;
   if((direction > 0 && resistance > entry && resistance < take_profit) ||
      (direction < 0 && support < entry && support > take_profit))
   {
      opportunity.reason = "Nearby support/resistance blocks target";
      return false;
   }
   opportunity.target_clearance_acceptable = true;

   double pullback_distance = MathMin(MathAbs(rates[0].close - ema20[0]), MathAbs(rates[0].close - ema50[0])) / atr[0];
   double pullback_quality = MathMax(0.0, 1.0 - pullback_distance / MathMax(0.1, pullback_atr_tolerance + 0.5));
   double spread_quality = MathMax(0.0, 1.0 - spread / maximum_spread);
   double trend_separation = MathMin(1.0, MathAbs(ema20[0] - ema50[0]) / atr[0]);
   double rsi_quality = direction > 0
      ? MathMax(0.0, MathMin(1.0, (rsi[0] - rsi_buy_min) / MathMax(1.0, rsi_buy_max - rsi_buy_min)))
      : MathMax(0.0, MathMin(1.0, (rsi_sell_max - rsi[0]) / MathMax(1.0, rsi_sell_max - rsi_sell_min)));
   double adx_quality = use_adx ? MathMax(0.0, MathMin(1.0, (adx[0] - adx_minimum) / 20.0)) : 0.5;
   bool higher_agrees = direction > 0 ? higher_buy : higher_sell;
   double target_clearance = direction > 0 ? (resistance - entry) / target_distance : (entry - support) / target_distance;
   double clearance_quality = MathMax(0.0, MathMin(1.0, target_clearance));
   double candle_quality = direction > 0
      ? (rates[0].close > rates[0].open ? 1.0 : 0.0)
      : (rates[0].close < rates[0].open ? 1.0 : 0.0);
   double score = 20.0 + trend_separation * 10.0 + (higher_agrees ? 10.0 : 0.0) +
                  pullback_quality * 20.0 + rsi_quality * 10.0 + candle_quality * 15.0 +
                  adx_quality * 10.0 + spread_quality * 10.0 + clearance_quality * 5.0;
   opportunity.score_applicable = true;
   if(score < minimum_score)
   {
      opportunity.reason = "Setup score below minimum";
      return false;
   }
   opportunity.score_acceptable = true;

   opportunity.direction = direction;
   opportunity.score = MathMin(score, 100.0);
   opportunity.atr = atr[0];
   opportunity.spread = spread;
   opportunity.entry = entry;
   opportunity.stop_loss = stop_loss;
   opportunity.take_profit = take_profit;
   opportunity.reward_risk = target_distance / stop_distance;
   opportunity.reason = direction > 0 ? "Confirmed trend pullback BUY" : "Confirmed trend pullback SELL";
   return true;
}

#endif