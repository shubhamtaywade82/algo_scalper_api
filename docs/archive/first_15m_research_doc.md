I want to check one thing ime on nifty 15m  first candle high and low breakes and stay below if crossed dow the first 15m candle and stays above when crossed high of the first 15m candle

Yes. This is exactly the type of research your **Research Kernel** should perform. Rather than assuming the first 15-minute breakout works, you can measure its historical edge.

## Research Objective

For each of the last **90 trading days**:

1. Get 1-minute OHLCV data.
2. Identify the first 15-minute candle (9:15–9:30).
3. Record:

   * First15 High
   * First15 Low
4. Watch the rest of the day.
5. Determine whether:

   * High breakout occurred.
   * Low breakdown occurred.
   * Breakout sustained.
   * False breakout.
   * No breakout.

---

## Define "Working"

This is the most important part. You need an objective definition.

Example:

### Bullish

A bullish breakout is considered successful if:

```
Close > First15High

AND

Within next N candles
price moves >= X%
before
falling back below First15High
```

Example:

```
First15 High = 25020

10:05
Close = 25025

Next 30 minutes

Highest = 25100
Gain = +80 points

Never closes below 25020

SUCCESS
```

---

### Bearish

```
Close < First15Low

Then

Falls another
40
60
80
100 points

before reclaiming First15Low
```

---

## Daily Classification

Every day becomes one record.

| Date | High Break | Low Break | Sustained | Failed | Max Move | Result |
| ---- | ---------- | --------- | --------- | ------ | -------- | ------ |
| Day1 | Yes        | No        | Yes       | No     | +145 pts | Win    |
| Day2 | Yes        | No        | No        | Yes    | +18 pts  | Loss   |
| Day3 | No         | Yes       | Yes       | No     | -112 pts | Win    |

After 90 days:

```
90 trading days

Bullish breakout days

42

Successful

31

Failed

11

Probability

73.8%
```

Likewise for bearish breakouts.

---

## Much Better Metrics to Compute

Don't stop at win rate.

Calculate:

### Breakout Frequency

```
How many days broke High?

How many broke Low?

How many never broke?
```

---

### Sustained Probability

```
P(
Stay above High
|
Break High
)
```

This is much more useful than raw win rate.

---

### False Break Probability

```
Break High

↓

Return inside range

↓

Close below range
```

Percentage of false breakouts.

---

### Average Extension

After breakout:

```
Average move

Maximum move

Median move
```

Example

```
Average

58 points

Median

44 points

Maximum

212 points
```

---

### Time Analysis

When did breakout occur?

```
9:30

10:00

11:15

1:45

2:50
```

You may discover:

```
9:30 breakouts

82% success

11:45 breakouts

41%

2:30 breakouts

22%
```

That becomes another trading filter.

---

## Volatility Context

Store:

* ATR
* ADX
* Gap Up/Down
* Previous Day High/Low
* VWAP location
* Opening Range Size

Then answer questions like:

```
Does the setup work better on
high ATR days?

Does it fail on inside days?

Does it work after gap ups?

Does ADX > 25 improve probability?
```

---

## Research Output

Instead of just saying "it works", your engine should produce results like:

```
First 15m Breakout Research

Period

90 Days

Bullish Breakouts

46

Successful

35

Probability

76.1%

Average Gain

82 pts

Average Failure

21 pts

False Break Rate

23.9%

Best Breakout Time

9:45-10:15

Best ATR

>18

Best ADX

>25

Best Opening Range

40-65 pts

No Breakout Days

19
```

## Recommendation

Don't limit this to 90 days because the API does. Build the Research Kernel to process **90-day windows**, persist the results in your database, and repeat over time. After a year, you'll have 360+ trading days of statistics. This aligns with the architecture you've been designing for `algo_scalper_api`: the DhanHQ client supplies the raw OHLCV data, and your Research Kernel continuously builds a statistically validated model of when the first 15-minute breakout has a genuine edge.
Create a ruby script which shows the results Yes. I would make this a standalone research script under your `algo_scalper_api` so it can later be plugged into the Research Kernel.

## Suggested structure

```
lib/
└── research/
    └── first_15m_breakout.rb
```

Run:

```bash
bundle exec ruby lib/research/first_15m_breakout.rb
```

---

## What the script does

1. Fetch last **90 trading days** of **1-minute OHLCV** from DhanHQ.
2. Group candles by trading day.
3. Determine the first 15-minute range.
4. Detect:

   * High breakout
   * Low breakout
   * False breakout
   * Sustained breakout
5. Calculate:

   * Success %
   * Failure %
   * No breakout %
   * Average move
   * Maximum move
6. Print a detailed report.

---

## Configuration

```ruby
UNDERLYING      = "NIFTY"
TIMEFRAME       = "1"
LOOKBACK_DAYS   = 90

# Breakout confirmation
CONFIRM_CLOSE   = true

# Target
TARGET_POINTS   = 50

# Stop condition
RETURN_TO_RANGE = true
```

---

## Core algorithm

```ruby
days.each do |day|
  first15 = day.first(15)

  high = first15.map(&:high).max
  low  = first15.map(&:low).min

  state = :inside

  day.drop(15).each do |candle|

    if candle.close > high
      state = :bull_breakout
      break
    elsif candle.close < low
      state = :bear_breakout
      break
    end
  end
end
```

---

## Bullish evaluation

```ruby
entry = breakout.close

future = remaining_candles

highest = future.map(&:high).max
lowest  = future.map(&:low).min

gain = highest - entry

failed = future.any? { |c| c.close < first15_high }

success = gain >= TARGET_POINTS && !failed
```

Bearish is the mirror image.

---

## Metrics

The script should calculate:

```text
Trading Days

Bull Breakouts

Bear Breakouts

Bull Success %

Bear Success %

Bull Failure %

Bear Failure %

False Break %

Average Move

Median Move

Maximum Move

No Breakout Days

Average Breakout Time

Average Range Size

Largest Opening Range

Smallest Opening Range
```

---

## Daily output

```text
2026-04-18

IB High : 24985
IB Low  : 24931

Breakout : HIGH

Time : 09:47

Highest : 25078

Move : +93 pts

Returned into range : NO

Result : SUCCESS
```

---

## Final report

```text
===================================================

FIRST 15 MINUTE BREAKOUT RESEARCH

===================================================

Underlying

NIFTY

Trading Days

90

Bull Breakouts

44

Successful

34

Success Rate

77.27 %

False Breakouts

10

Bear Breakouts

39

Successful

28

Success Rate

71.79 %

No Breakout Days

7

Average Bull Move

82.4 pts

Average Bear Move

74.9 pts

Maximum Bull Move

248 pts

Maximum Bear Move

211 pts

Average Breakout Time

09:46

Average First15 Range

54 pts

===================================================
```

## Extend the research

Since you're already building a Research Kernel, don't stop at breakout statistics. Persist these additional features for every trading day:

* First 15-minute range size.
* Gap up/down percentage.
* Previous day's high/low relationship.
* VWAP position at breakout.
* ATR and ADX at breakout.
* RSI, MACD, Supertrend state.
* Day of week.
* Expiry proximity (weekly/monthly).
* Opening volume.

With these features, you'll be able to answer questions such as:

* Does the setup work better on expiry days?
* Does a smaller opening range produce stronger trends?
* Is ADX > 25 a significant filter?
* Which weekdays have the highest probability?
* What combination of market conditions produces the highest expectancy?

This transforms the script from a simple backtest into a reusable research engine that can continuously discover statistically significant filters for your options-buying strategies.
List similar different concepts @Web search for options buying or understanding how will the index playout for a dayFor **options buying**, you are not looking for entry indicators—you are looking for **market context models** that answer:

> **"What kind of day is today likely to become?"**

Institutional traders classify the session before looking for entries. Below are the most useful concepts that you can backtest using your DhanHQ data.

| Concept                      | Purpose                                      | Research Value             |
| ---------------------------- | -------------------------------------------- | -------------------------- |
| Opening Range Breakout (ORB) | Break of first 5/15/30 min range             | High                       |
| Initial Balance (IB)         | First hour range defines auction             | High ([Market Profile][1]) |
| Market Profile Day Types     | Predict trend day vs range day               | Very High ([Reddit][2])    |
| CPR (Central Pivot Range)    | Predict trending vs sideways sessions        | Very High                  |
| Gap Analysis                 | Gap continuation vs gap fill                 | Very High                  |
| VWAP Regime                  | Institutions buying/selling                  | High                       |
| Opening Drive                | Strong move from open                        | High                       |
| Previous Day Levels          | Acceptance or rejection of yesterday's value | High                       |
| Opening Range Width          | Narrow ranges often precede expansion        | High ([TradeTerminal][3])  |
| Volatility Regime            | ATR expansion/contraction                    | High                       |

## 1. Opening Range Breakout (ORB)

Exactly what you're researching.

Questions to answer:

* Does first 15m high break?
* Does it sustain?
* How many points after breakout?
* Does breakout fail?
* Time of breakout?

Backtest probability over 90 days. ([BreakOrb][4])

---

## 2. Initial Balance (IB)

Instead of only using 15 minutes, use the **first hour**.

Research:

* IB width
* IB breakout
* Range extension
* Double IB break
* Failed IB break

Market Profile practitioners treat the Initial Balance as a key reference for the rest of the session. ([Market Profile][1])

---

## 3. Market Profile Day Types

This is one of the highest-value research areas.

Classify every day as:

* Trend Day
* Double Distribution Trend
* Normal Day
* Normal Variation Day
* Neutral Day
* Non-Trend Day

Then ask:

> Which indicators are present before each day type? ([Reddit][2])

---

## 4. Gap Analysis

Every morning classify:

```text
Gap Up

Gap Down

Inside Gap

Outside Gap
```

Then measure:

* Gap Fill %
* Gap Continuation %
* Average continuation
* Average reversal

---

## 5. CPR Analysis

Classify CPR as:

* Narrow CPR
* Wide CPR
* Overlapping CPR
* Higher CPR
* Lower CPR

Research:

* Narrow CPR → Trend probability?
* Wide CPR → Range probability?

---

## 6. Previous Day Levels

Track:

* Previous High
* Previous Low
* Previous Close
* Previous VWAP

Questions:

* Does breaking PDH lead to trend?
* Does rejection at PDL reverse?
* Does reclaiming yesterday's close change direction?

---

## 7. VWAP Behaviour

Measure:

* Above VWAP all day
* Below VWAP all day
* VWAP cross count
* Distance from VWAP

Questions:

* Trend days stay on one side?
* Range days oscillate around VWAP?

---

## 8. Opening Drive

Institutional concept.

Classify first 30 minutes:

* Open Drive Up
* Open Drive Down
* Open Test Drive
* Open Auction
* Open Rejection Reverse

Then compute probabilities.

---

## 9. Opening Range Width

Measure:

```text
First 15m Range

Average 20-day Range

Ratio
```

Research:

* Narrow opening → Trend?
* Wide opening → Mean reversion?

---

## 10. Volatility Regime

Measure:

* ATR
* Historical Volatility
* Opening Range %
* VIX (if available)

Questions:

* Does ATR expansion improve ORB?
* Does low ATR lead to false breakouts?

---

## 11. Option Chain Context

Since you're trading options, integrate:

* ATM IV
* IV Rank
* PCR
* Max Pain
* OI Change
* OI Buildup
* Call/Put Writing

Research whether these improve breakout probability.

---

## 12. Multi-Timeframe Alignment

For every breakout, record:

* 5m trend
* 15m trend
* 1h trend
* Daily trend

Questions:

* Does 15m ORB perform better when all higher timeframes align?

---

# Research Matrix

Instead of one strategy, build a **daily feature vector**.

```text
Trading Day

├── Gap
├── Opening Range
├── First 15m High
├── First 15m Low
├── IB Width
├── CPR Width
├── VWAP Position
├── ATR
├── ADX
├── RSI
├── MACD
├── Supertrend
├── Previous Day High
├── Previous Day Low
├── Option Chain
├── OI Change
├── IV
├── Day Type
└── Final Outcome
```

This produces one dataset row per day.

After hundreds of sessions, you can answer questions such as:

* "When ADX > 25 and the first 15-minute range is narrow, what is the probability of a sustained breakout?"
* "How often does a gap-up above the previous day's high become a trend day?"
* "Which combination of CPR width, VWAP position, and opening range produces the highest expectancy for ATM option buying?"

Given your `algo_scalper_api` architecture, this is the direction I would take. Rather than building isolated strategies, build a **Research Kernel** that extracts 50–100 daily features from OHLCV and option-chain data, labels the session outcome, and computes conditional probabilities. That creates a reusable statistical foundation for every options-buying strategy you develop.

[1]: https://marketprofile.info/articles/initial-balance-breakout-strategy?utm_source=chatgpt.com "Initial Balance Breakout Strategy for Day Traders (2026)"
[2]: https://www.reddit.com/r/IndianStockMarket/comments/relu36/the_types_of_market_days_ultimate_guide_to/?utm_source=chatgpt.com "The Types of Market Days - Ultimate guide to different trading days"
[3]: https://tradeterminal.org/strategies/opening-range-breakout?utm_source=chatgpt.com "Opening Range Breakout Strategy — Futures Trading Setup Explained | TradeTerminal"
[4]: https://breakorb.com/blog/opening-range-breakout-strategy-guide.html?utm_source=chatgpt.com "Opening Range Breakout Strategy Guide 2026 | BreakOrb"
Also there is a veey high chance of atm premiums moving 50% to 100% + inthe first 15 mins eg today can our system I.e. AlgoScalperApi  capture such moves ? And if we get this move we are done for the day how can we identify such moves ?
Yes—but not by trying to predict **every** 50–100% move. Instead, you build a system that identifies the **market conditions under which those explosive moves are statistically likely**.

Looking at your screenshots:

* The **NIFTY 15m chart** shows a sharp rejection immediately after the open.
* The **ATM CALL premium** collapsed from roughly ₹200+ to below ₹100 in one 15-minute candle (over 50%).
* That happened because **ATM options have high gamma**, so a relatively small underlying move near the open can produce a very large premium move.

This is exactly the type of move your `AlgoScalperApi` should be designed to capture.

---

# Instead of "Trading"

Your system's job should be:

> **Predict whether today is likely to become a High Expansion Day.**

Not:

> Buy because RSI crossed.

This is a fundamental architectural difference.

---

# Research Question

Instead of asking:

> Does Supertrend work?

Ask:

> **What did the market look like at 9:15 before every 50% ATM option move?**

If you research the last 365 trading days you'll probably find recurring patterns.

---

# Build a Daily Feature Vector

At 9:15, capture:

```
Gap %

Opening Range

ATR

Previous Day Range

Previous Day High

Previous Day Low

Previous Close

VWAP

ADX

RSI

Supertrend

EMA Stack

Bollinger Width

Opening Volume

Option Chain PCR

ATM IV

ATM Delta

OI Build-up

Market Breadth

India VIX

Expiry Day

Day of Week

Opening Auction Imbalance
```

---

# Then Label the Day

```
ATM CE

+50%

YES

ATM CE

+100%

YES

ATM PE

+50%

NO

Trend Day

YES

Range Day

NO

```

Now every day becomes one row in your research database.

---

# Then Ask Questions

Examples:

### Question 1

```
When

Gap Down

+

ADX > 25

+

Opening Range < 45 points

+

Below Yesterday Low

↓

Probability of

ATM Put >50%
```

---

### Question 2

```
When

First 15m breaks

↓

How often

ATM premium doubles?
```

---

### Question 3

```
When

Opening Drive Down

↓

How often

Trend Day?
```

---

# The Research Kernel

Instead of hardcoding rules, compute probabilities.

Example output:

```
Condition

Gap Down >0.4%

ADX >28

ATR Expanding

Below VWAP

Below Yesterday Low

↓

Observed

73 Days

↓

ATM PE >50%

59 Days

↓

Probability

80.8%
```

Now your strategy has statistical backing.

---

# Research More Than Winners

Also research **losers**.

Example:

```
Gap Up

ADX 12

Wide CPR

Inside Yesterday Range

↓

Only

14%

Chance

ATM Premium >50%
```

Those are days to avoid trading.

---

# Detecting the Move in Real Time

Instead of one signal, require a confluence.

```
Market Open

↓

Opening Regime

↓

Trend Probability

↓

Expansion Probability

↓

Directional Bias

↓

Option Selection

↓

Entry

↓

Risk Manager
```

For example:

```
Trend Score

92/100

Expansion Score

89/100

Bullish Score

15/100

Bearish Score

94/100

Recommended

Buy ATM Put
```

---

# A Better Architecture for AlgoScalperApi

Instead of:

```
Indicators

↓

Buy Signal
```

Build:

```
Market Data

↓

Feature Extractor

↓

Research Engine

↓

Probability Engine

↓

Trade Opportunity Detector

↓

Risk Manager

↓

Execution
```

The **Probability Engine** should answer:

* Is today likely to trend?
* Is today likely to expand?
* Bullish or bearish expansion?
* Expected move in the underlying (points).
* Expected ATM option move (%).
* Expected holding time.
* Confidence score.

---

## One Critical Improvement

Because you already have access to **historical option premiums** from the DhanHQ client, don't research only the **index**.

Research **both simultaneously**.

For every trading day, store:

| Index Feature   | Option Feature      |
| --------------- | ------------------- |
| Gap %           | ATM CE open premium |
| First 15m range | ATM PE open premium |
| ATR             | CE max gain %       |
| ADX             | PE max gain %       |
| VWAP            | Time to +50%        |
| Trend direction | Time to +100%       |
| Closing range   | Maximum drawdown    |

This lets you answer questions that are directly relevant to options buying, such as:

* Which opening conditions produce **ATM premiums that reach +50% within the first hour**?
* How often does an initial breakout continue far enough for **+100% premium expansion**?
* Which days produce **large index moves but poor option returns** because of IV contraction?
* How do expiry days differ from non-expiry days?

That shifts `AlgoScalperApi` from being an indicator-driven trading bot to a **market research platform** that continuously learns which opening conditions historically produced the large ATM option moves you're trying to capture.

No I was talking about capitaing the moves in the first 15 min itself

That changes the problem significantly.

You're asking:

> **Can AlgoScalperApi identify and enter during the first 15 minutes so we capture the entire 50–100% ATM option move?**

The answer is **yes, but only if you stop waiting for confirmation candles.**

The biggest option moves often happen **inside** the first 15 minutes. If your system waits for the first 15-minute candle to close, you've already missed much of the premium expansion.

## Instead of an "Opening Range Breakout"

Think of it as an **Opening Auction Detection Engine**.

The system should make a decision between **9:15:00 and 9:18:00**, not 9:30.

## The problem

Suppose NIFTY opens at 24,150.

Between 9:15 and 9:20:

* Strong selling enters.
* VWAP is lost immediately.
* Market breadth is weak.
* Successive 1-minute candles make lower highs.
* ATM Put goes from ₹110 → ₹170 (+55%).

By 9:30, it may already be ₹220–₹250.

Waiting for the first 15-minute candle confirmation is too late.

---

## What should AlgoScalperApi do?

Build an **Opening Momentum Engine**.

Every second (or every completed 1-minute candle), evaluate:

```text
09:15:00
↓

Opening Gap

↓

Opening Volume

↓

1-minute candle strength

↓

VWAP relationship

↓

Order flow (if available)

↓

Option premium acceleration

↓

Probability Score

↓

BUY
```

---

## Research this

For every day where an ATM option gained more than 50% in the first 15 minutes, record:

* Gap size.
* First 1-minute candle.
* First 3-minute candle.
* First 5-minute candle.
* VWAP position.
* Distance from previous day's high/low.
* Opening volume.
* ATR.
* ADX (from prior session or rolling intraday).
* Time when the option first gained 20%.

Then ask:

> **What did these days have in common before the move started?**

---

## A scoring model

Don't rely on one indicator. Use a score.

Example:

| Condition                          | Score |
| ---------------------------------- | ----: |
| Gap > 0.5%                         |   +15 |
| First 1m body > average            |   +10 |
| Second candle continues            |   +10 |
| Below VWAP                         |   +10 |
| Previous day low breaks            |   +15 |
| Option premium +10% in first 2 min |   +20 |
| Volume > 2× average                |   +10 |
| RSI momentum                       |    +5 |
| Bollinger Band expansion           |    +5 |

Total:

```text
Score = 90/100

BUY ATM PUT
```

---

## Option premium itself is a signal

Since you're trading options, don't ignore the option chart.

Monitor:

* Premium velocity (%/minute).
* Volume surge.
* OI changes (where available).
* Bid-ask spread.
* Delta acceleration.

Sometimes the option premium tells you more than the underlying during the opening auction.

---

## One caution

The screenshots you shared show **successful** explosive moves. There will also be many mornings where the market makes a sharp move for 2–3 minutes and then completely reverses.

Before building an opening-entry strategy, your Research Kernel should answer questions like:

* Out of the last 365 trading days, how many had ATM options move **+50% within the first 15 minutes**?
* Of those, how many **continued** versus **reversed**?
* What is the maximum adverse excursion after an early entry?
* What combination of opening conditions distinguished the winners from the failures?

If your research finds, for example, that only 20–30 days per year exhibit this behavior but they share consistent characteristics, then AlgoScalperApi can be optimized to trade only those high-probability opening auction days and stand aside on the rest. That is a much more robust objective than attempting to trade every market open.

I want to find out such days when underlying moves aggressively in the first 15m using 1m and 15m and the actual tradable derivative that is the atm premiums moves hpwmuch in these days etc and we then develop rules to capture such moves using the previous day behaviour, gap ups/downs etc etc execution timeframes, context that should be valid which will approve this entry etc etc @Thinking

Yes. That is the correct research target: **identify mornings where the underlying becomes “high-expansion” inside the first 15 minutes, then measure how far the ATM option actually runs in that same window**. The opening range is a real framework here; Mark Fisher’s ACD style explicitly uses the first 15 minutes as the opening range, and breakout logic is built around that range. ([Investopedia][1])

## What to research

For each trading day, label **two things** separately:

1. **Underlying aggression**: did NIFTY break the first 15m high/low and continue?
2. **Derivatives payoff**: did the ATM CE/PE move +25%, +50%, +75%, +100% inside the first 15m or first 30m?

That separation matters because the index can be “correct” while the option move is weak, or the index move can be modest while gamma makes the ATM premium explode.

## What features should define these days

Use the morning context only, before the trade:

* Gap up / gap down versus previous close. A gap is the no-trade space between sessions, and gaps are meaningful when spotted before the move begins. ([Wikipedia][2])
* Previous day high / low / close.
* First 1m, 3m, 5m impulse.
* First 15m range width.
* Opening volume versus rolling baseline. Volume is commonly used to confirm breakouts and breakdowns. ([Investopedia][3])
* Volatility regime via ATR. ATR measures volatility, not direction, and is useful for identifying breakout-prone conditions. ([Investopedia][4])
* VWAP location. VWAP is an intraday, volume-weighted benchmark often used to judge short-term execution and price location. ([Investopedia][5])
* Market structure context: inside previous day range, above/below previous day high/low, and whether the opening is a trend-start or a failed move.
* Option-chain context if available: ATM premium velocity, delta expansion, and whether the premium is accelerating faster than the index.

## How to define an “approved entry”

Do **not** approve a trade from a single candle. Require a confluence score.

### Bullish approval

Approve a **CE** only if most of these are true inside the first 1m–5m window:

* Opening gap is not strongly bearish.
* First 1m/3m candles hold above VWAP.
* Price takes out the opening range high.
* Breakout candle closes strong, not as a wick.
* Opening volume expands versus the recent baseline. ([Investopedia][3])
* Previous day high is reclaimed or about to be breached.
* ATM CE premium is already accelerating, not just drifting.

### Bearish approval

Mirror the same logic for **PE**:

* Weak or bearish gap.
* Price holds below VWAP.
* Opening range low breaks.
* Strong close below the range.
* Volume expands.
* Previous day low is lost or under pressure.
* ATM PE premium is accelerating.

## What your system should output

For every day, calculate:

* Probability the underlying trends in the first 15m.
* Probability ATM CE hits +50% in the first 15m.
* Probability ATM PE hits +50% in the first 15m.
* Probability of +100% move.
* Average time to target.
* False-break rate.
* Maximum favorable excursion and maximum adverse excursion.

That gives you a clean classification like:

* **Trend morning / expansion morning**
* **Fakeout morning**
* **Range morning**
* **Low-volatility chop**

## Important caution

A regime classifier can be useful descriptively, but profitability is not guaranteed. Recent research on intraday regime classification using first-30-minute return, gap size, and opening volume found that those features can identify distinct day types, but directional strategies still failed validation after transaction costs and consistency checks. ([arXiv][6])

## Best framing for AlgoScalperApi

Your system should become:

**Feature extraction → opening regime classification → option expansion probability → entry approval → execution**

Not:

**indicator signal → immediate trade**

That is the right architecture for catching these first-15-minute ATM expansions.

If you want, I can turn this into a **precise research schema + Ruby backtest script** that scores each day and prints the probability of CE/PE +50%, +75%, and +100% within the first 15 minutes.

[5]: https://www.investopedia.com/articles/trading/11/trading-with-vwap-mvwap.asp?utm_source=chatgpt.com "Trading With VWAP and MVWAP"
[6]: https://arxiv.org/abs/2605.11423?utm_source=chatgpt.com "A Validated Volatility-Volume-Gap Classifier for Regime Identification in MNQ Intraday Data"

I think this is the correct direction for `AlgoScalperApi`. However, I would make one important change.

**Don't research strategies first. Research market phenomena first.**

Your research question becomes:

> **"What characteristics do days have where an ATM option moves 50–100% within the first 15 minutes?"**

Once you answer that statistically, the trading rules become much easier.

---

# Phase 1 — Build the Research Dataset

Every trading day becomes **one research record**.

```
Trading Date
│
├── Previous Day Context
├── Overnight Context
├── Opening Context
├── First 15m Context
├── Underlying Behaviour
├── ATM Option Behaviour
└── Final Labels
```

---

# Previous Day Features

These are known **before the market opens**.

```
Previous Day

High
Low
Close
Open

Range

Body Size

Upper Wick

Lower Wick

Trend

ATR

ADX

RSI

MACD

Supertrend

VWAP

Volume

Day Type

Trend
Range
Inside
Outside

CPR Width

Value Area

POC

Distance From EMA20

Distance From EMA50

Distance From EMA200
```

---

# Overnight Context

```
Gap

Gap %

Gap Up

Gap Down

Gap Inside

Gap Outside

Global Markets

SGX/Nifty Futures

India VIX

Expiry?

Weekly

Monthly

Holiday?

Monday?

Friday?
```

---

# Opening Context

Using 1-minute candles.

```
First Candle

Range

Body %

Upper Wick %

Lower Wick %

Volume

VWAP

Open Interest

Delta

Gamma

Premium Velocity
```

---

# First 15 Minute Features

```
15m High

15m Low

15m Range

Range %

Number Green Candles

Number Red Candles

Average Volume

Largest Candle

Average Body

ATR

VWAP Position

EMA Stack

ADX

RSI

Supertrend
```

---

# Underlying Behaviour

This becomes your **label**.

```
Underlying

Moved

20

30

40

50

75

100 Points

Inside 15 Minutes

YES / NO

Trend?

YES / NO

Reversal?

YES / NO
```

---

# ATM Option Behaviour

Now comes the important part.

Store **actual tradable results**.

```
ATM CE

Open

Highest

Lowest

Close

Maximum Gain %

Maximum Drawdown %

Time To

20%

30%

50%

75%

100%

Time Of High

Volume

ATM PE

Same Fields
```

This is what matters.

Not the index.

The tradable instrument.

---

# Labels

Now classify every day.

Example

```
Trend Explosion

YES

ATM CE >50%

YES

ATM PE >50%

NO

Best Trade

CALL

Time

09:17

Maximum Gain

128%
```

---

# Phase 2 — Discovery

Now don't build rules.

Ask questions.

Example

```
Show me every day where

ATM CE

>

80%

inside

15 minutes
```

Maybe only

```
18 days
```

Now compare those

18 days.

---

Ask

```
What was common?
```

Maybe

```
Gap Up

17/18

ADX > 28

16/18

Opening Range

<45 points

17/18

Above Previous High

15/18

First Candle

Bullish

18/18
```

Now you have facts.

---

# Phase 3 — Feature Importance

Now compute

```
P(

ATM CE >50%

|

Gap Up
)
```

Then

```
P(

ATM CE >50%

|

Gap Up

AND

ADX >25
)
```

Then

```
P(

ATM CE >50%

|

Gap Up

AND

ADX >25

AND

VWAP Above

AND

Opening Volume >2x
)
```

Keep increasing conditions.

Eventually

```
Probability

87%
```

Now you've discovered a setup.

Not invented one.

---

# Phase 4 — Build an Entry Engine

Only now.

```
Market Opens

↓

Extract Features

↓

Score Every Feature

↓

Compare With Research

↓

Probability

↓

Entry

↓

Risk

↓

Exit
```

---

# The Biggest Upgrade

I would go one step further.

Instead of manually looking for patterns, build a **Market DNA Database**.

Each trading day is stored as a feature vector.

For example:

```json
{
  "date": "2026-07-14",
  "previous_day": {
    "trend": "bullish",
    "range": 242,
    "adx": 31,
    "atr": 128
  },
  "opening": {
    "gap": -0.62,
    "opening_range": 36,
    "volume_ratio": 2.8
  },
  "first_15m": {
    "direction": "bearish",
    "move_points": 74,
    "vwap": "below",
    "break_previous_low": true
  },
  "atm_option": {
    "type": "PE",
    "entry": 118.50,
    "high": 243.20,
    "gain_pct": 105.2,
    "time_to_50pct": "09:22",
    "time_to_100pct": "09:28"
  }
}
```

After 500–1000 trading days, you don't need to guess. You can query the database like a quant researcher:

* "Show all days where ATM PE gained more than 75% before 9:30."
* "What opening conditions occurred in at least 80% of those days?"
* "Which features have the highest predictive power?"
* "Which combinations produce the best expectancy and the lowest false-break rate?"

## I would structure the Research Kernel into six independent modules

1. **Market Snapshot Extractor** – builds all features before and during the first 15 minutes.
2. **Option Performance Analyzer** – measures the actual CE/PE opportunity.
3. **Day Classifier** – labels the session (trend, reversal, gap continuation, etc.).
4. **Pattern Discovery Engine** – groups statistically similar days.
5. **Probability Engine** – computes conditional probabilities for every feature combination.
6. **Rule Generator** – converts statistically validated patterns into executable entry rules for `AlgoScalperApi`.

This architecture keeps research separate from execution. The trading engine never invents rules—it only trades setups that the research layer has already demonstrated to have a measurable historical edge.
Also premiums can decays after reaching the high so we need to be precise on exiting once reached max premium though we cannot identify the peak but somthing which can help Atleast capture most of the moveI think this is the missing piece. You're not just researching **entries**; you're researching the **entire lifecycle** of an explosive options move.

For options buying, there are actually **three separate prediction problems**:

1. **Will an explosive move happen?** (Entry)
2. **Is the move still healthy?** (Hold)
3. **Is the move exhausting?** (Exit)

Most systems only solve #1.

---

# Think in Terms of a Trade Lifecycle

```
Research
      ↓
Entry Probability
      ↓
Trade
      ↓
Expansion Monitoring
      ↓
Exhaustion Detection
      ↓
Exit
```

Instead of finding "the top", detect when the **probability of further expansion becomes low**.

---

# Research the Entire Premium Path

For every winning day, don't just store:

```
Entry = ₹100

Highest = ₹220
```

Store the entire journey.

```
09:15  100

09:16  112

09:17  128

09:18  150

09:19  176

09:20  195

09:21  214

09:22  220  ← Peak

09:23  212

09:24  205

09:25  190
```

Now calculate:

* Velocity
* Acceleration
* Pullback %
* Time between highs
* Volume
* Underlying movement

This becomes your **Premium Expansion Curve**.

---

# Research Questions

For every trade, calculate:

## Entry

```
Time

Premium

Underlying

Indicators
```

---

## Maximum Favorable Excursion (MFE)

```
Highest Premium

Highest %

Time to High
```

---

## Maximum Adverse Excursion (MAE)

```
Worst drawdown after entry
```

---

## Exit Quality

Now compare exits.

Example:

```
Peak

220

Exit

212

Captured

96%

Excellent
```

Another

```
Peak

220

Exit

165

Captured

75%

Poor
```

Now your research measures **how much of the move your exit retained**.

---

# Build an Exit Efficiency Metric

```
Peak Premium

220

Exit Premium

205

Capture %

93.2%
```

This should become one of the primary KPIs.

---

# What Happens Before Tops?

Research the last 200 winning trades.

Look 1–3 candles **before the peak**.

Maybe you discover:

```
Premium

Higher High

Underlying

Not Higher High

↓

Bearish Divergence
```

Or

```
Premium

Making High

Volume

Dropping

↓

Exit
```

Or

```
Underlying

Still Rising

Premium

Stops Rising

↓

Gamma Exhaustion
```

Those are research questions, not assumptions.

---

# Candidate Exit Features

Your Research Kernel should test whether any of these consistently occur before premium peaks:

### Option Features

* Premium velocity slowing.
* Premium acceleration turns negative.
* Large upper wick.
* Failure to make new highs.
* Consecutive lower highs.
* Volume decreases.
* Delta stops increasing.

---

### Underlying Features

* Momentum slowing.
* ATR contraction.
* VWAP rejection.
* EMA crossover.
* RSI divergence.
* MACD histogram weakening.
* Bollinger Band mean reversion.

---

### Multi-Timeframe

1m:

```
Strong
```

3m:

```
Weakening
```

5m:

```
Bearish engulfing
```

That combination may produce a high-quality exit.

---

# Exit Research is Separate

Don't reuse entry logic.

Build another engine.

```
Entry Engine

↓

Trade

↓

Exit Engine
```

They should be completely independent.

---

# A Better KPI

Instead of asking:

> "Did we exit at the top?"

Ask:

> **"What percentage of the available move did we capture?"**

Example:

```
Maximum Premium

220

Entry

100

Available

120

Exit

208

Captured

108

Efficiency

90%
```

A system that consistently captures **85–90% of the available expansion** is much more realistic than trying to identify the exact peak.

---

# I Would Add a Fourth Research Module

Your current research naturally becomes:

```
Market Research
        ↓
Entry Research
        ↓
Trade Research
        ↓
Exit Research
```

Where **Exit Research** continuously evaluates:

* Which exit rule captured the highest percentage of MFE?
* Which exit rule had the smallest giveback?
* Which exit rule produced the highest expectancy?
* Which exit rule was most consistent across different market regimes?

This lets you compare exits objectively. For example:

| Exit Method                                         | Avg. Capture of MFE | Avg. Giveback | Win Rate |
| --------------------------------------------------- | ------------------: | ------------: | -------: |
| Fixed +50% target                                   |                 61% |            0% |     High |
| 20% trailing stop                                   |                 87% |           13% |   Medium |
| Supertrend exit                                     |                 82% |           18% |   Medium |
| Premium momentum decay                              |                 91% |            9% |     High |
| Hybrid (trail + momentum + underlying confirmation) |                 93% |            7% |  Highest |

That is the type of research output that can directly drive the exit logic in `AlgoScalperApi`, replacing intuition with measured evidence.
This screenshot is exactly why I think your research should be **option-centric**, not indicator-centric.

Let's reconstruct what happened.

### Timeline (approx.)

**09:15**

* NIFTY opens with strong bearish momentum.
* ATM 24050 CALL collapses immediately.
* Premium falls from around **₹190–200** to roughly **₹60** (about **-68%**).
* Most of the move happens within a few minutes.

Then:

* A bounce from ~₹60 to ~₹120 (+100% from the low).
* After that, premium continues decaying to around ₹60 as the underlying trend resumes.

This single day actually contains **two separate opportunities**:

1. The opening **ATM PUT** expansion (the one you want to capture).
2. The relief rally in the **ATM CALL** after panic selling (a different setup).

Your system should distinguish between them.

---

# This changes the research architecture

Don't research "entries."

Research **Expansion Events**.

Each expansion event should become a dataset.

Example:

```text
Date

2026-07-14

Type

Opening Expansion

Direction

Bearish

Underlying

-95 points

ATM PE

+118%

ATM CE

-68%

Expansion Started

09:15:08

Expansion Ended

09:22:41

Duration

7m 33s

Maximum Premium

₹238

Exit At

₹221

Capture

92.8%
```

Now every explosive move becomes one research sample.

---

# The second research dataset

For every expansion event store:

## Expansion

```text
Entry

Premium

Highest Premium

Time

Duration

Underlying Move

ATR

Gap

Volume

VWAP

Previous Day Context
```

---

## Decay

Now measure what happened **after the peak**.

```text
Peak

238

1 minute later

229

3 minutes

215

5 minutes

198

10 minutes

174

15 minutes

148
```

Now you know how quickly winners give back profits.

---

# This opens another research question

Instead of asking:

> Where is the peak?

Ask:

> **When does premium expansion statistically stop?**

Those are very different questions.

---

# Exit Research

For every trade test different exits.

Example.

## Exit A

```text
Fixed

50%

Average Capture

61%
```

---

## Exit B

```text
Trail

20%

Capture

88%
```

---

## Exit C

```text
Underlying loses EMA9

Capture

91%
```

---

## Exit D

```text
Premium loses EMA5

Capture

94%
```

---

## Exit E

```text
Premium closes below previous 2 lows

Capture

96%
```

Now compare them over hundreds of trades.

---

# One thing I would definitely add

Since you're trading **options**, your exit should not rely only on the underlying.

Track both simultaneously.

For example:

```text
Underlying

Still Falling

BUT

ATM PE

No New High

for 2 minutes

↓

Momentum exhausted

↓

Exit
```

Or

```text
Underlying

Makes New Low

ATM PE

Fails to Make New High

↓

Divergence

↓

Exit
```

That divergence between the underlying and the option premium may be one of the strongest exit signals because it often indicates **gamma expansion has peaked** even though price is still moving.

---

# I think AlgoScalperApi should eventually have five research engines

```text
Research Kernel

├── Market Context Research
│     (What type of day is this?)
│
├── Entry Research
│     (When do explosive moves start?)
│
├── Expansion Research
│     (How do option premiums accelerate?)
│
├── Exit Research
│     (How do we retain 85–95% of MFE?)
│
└── Risk Research
      (How much adverse movement occurs before success?)
```

## One more idea that I think will be valuable

Build an **Option Replay Engine**.

For every historical day, replay the market **second by second or minute by minute** exactly as it happened, but **hide the future** from the algorithm.

At each minute (09:15, 09:16, 09:17, ...), your engine should ask:

* Should I enter now?
* If already in, should I continue holding?
* Should I exit now?

Then compare those decisions against what actually happened afterward.

This avoids hindsight bias and lets you evaluate whether a rule genuinely captures early expansion while retaining most of the move. Over hundreds of replayed sessions, you'll know not just whether a rule works, but **how much of the available premium expansion it consistently captures**. That is a much stronger foundation for `AlgoScalperApi` than optimizing against end-of-day outcomes.
This screenshot actually reinforces the research direction.

The **ATM PUT** did exactly what a high-gamma ATM option does:

* **09:15**: Explosive expansion (large green candle).
* Premium peaks very quickly.
* Then it gives back a large portion of the move over the next few minutes.
* Afterwards it transitions into a slower trend.

This is why a conventional trailing stop often performs poorly during the opening auction. A 15–20% trail may either:

* get hit immediately due to the high volatility, or
* be so wide that it gives back too much profit.

## I think you should divide these into two different market phases

### Phase 1 — Opening Explosion (09:15–09:25)

Goal:

> Capture the gamma expansion.

Characteristics:

* Extremely high premium velocity.
* Large candles.
* Very high volatility.
* Large pullbacks are normal.

This phase needs its own entry and exit logic.

---

### Phase 2 — Intraday Trend

Goal:

> Ride the underlying trend.

This is where trailing stops, Supertrend, EMA, VWAP, etc. become much more useful.

These are fundamentally different problems.

---

# Research should measure both

For every expansion event calculate:

```text
Peak Premium

Peak Time

Time to Peak

Expansion %

Retracement %

Time to 25% Retracement

Time to 50% Retracement

Time to VWAP Cross

Time to EMA Cross
```

For today's example you might end up with something like:

```text
Entry

₹35

Peak

₹63

Gain

80%

Peak Time

09:16:40

09:18

₹54

09:20

₹49

09:25

₹43

09:30

₹38
```

Now compare hundreds of days.

---

# Instead of researching exits

Research **giveback**.

For every winning trade compute:

```text
Peak

63

Exit

58

Capture

92%
```

or

```text
Peak

63

Exit

42

Capture

55%
```

Now compare exit methods.

---

# One metric I would definitely add

For every trade calculate:

```text
Peak Premium

₹63

Exit Premium

₹58

Capture %

92%

Available Profit

₹28

Captured Profit

₹23

Profit Efficiency

82%
```

This becomes one of the primary optimization targets.

---

# The biggest insight

I actually think you're trying to discover something larger than an entry strategy.

You're trying to discover the **life cycle of an opening gamma expansion**.

Every expansion has four stages:

```text
Compression
        ↓
Ignition
        ↓
Expansion
        ↓
Exhaustion
```

The Research Kernel should identify:

* **Compression** – What conditions existed before the move?
* **Ignition** – What triggered the expansion?
* **Expansion** – How fast did the premium grow?
* **Exhaustion** – What consistently happened before the premium stopped making new highs?

---

## I would add one more module to the Research Kernel

Instead of only measuring the option premium, compute these derived metrics every minute:

| Metric                           | Why it matters                                                       |
| -------------------------------- | -------------------------------------------------------------------- |
| Premium Velocity (%/min)         | How fast the option is moving.                                       |
| Premium Acceleration             | Whether momentum is increasing or fading.                            |
| New High Frequency               | Time between successive premium highs.                               |
| Pullback Depth                   | Typical retracement during healthy trends.                           |
| Underlying-to-Premium Elasticity | How many % the premium moves for each 1-point move in NIFTY.         |
| Gamma Expansion Ratio            | How rapidly the ATM premium is expanding relative to the underlying. |
| Profit Capture Efficiency        | How much of the available MFE a given exit retains.                  |

One metric I find particularly interesting is **Underlying-to-Premium Elasticity**. Instead of only asking *"the premium went up 80%"*, ask:

> **How much did the ATM premium move for every 1-point move in the underlying during the first 15 minutes?**

On days where this elasticity is exceptionally high, you're observing exactly the type of opening gamma expansion you want `AlgoScalperApi` to specialize in. Those days should become a distinct class in your research database, because they are the sessions capable of producing outsized returns from ATM option buying.
@Thinking give me a indetailed claude code prompt which I can use this ask it to completely build and verifyand do a research using all this

Use this as a **Claude Code prompt**:

---

You are working inside the `AlgoScalperApi` codebase. Your task is to **design, implement, verify, and document a complete research engine** for detecting and analyzing **aggressive first-15-minute NIFTY moves** and the corresponding **ATM option premium expansion and decay**.

You must treat this as a serious quant-research and trading-systems task, not a toy script.

## Objective

Build a research system that can:

1. Pull historical OHLCV data for NIFTY and ATM option contracts using the DhanHQ client/gem already present or available in the repository.
2. Detect days where the **underlying moves aggressively in the first 15 minutes**.
3. Measure how much the **ATM CE/PE premium** expanded during that same first 15-minute window.
4. Measure premium decay after the peak so we can understand how much of the move can realistically be captured.
5. Derive statistical rules and entry/exit conditions from historical evidence.
6. Verify the logic using reproducible backtests and tests.
7. Produce research outputs in a clean, inspectable format.

---

## Core research questions

The system must answer these questions from historical data:

* On which days did NIFTY make a strong directional move in the first 15 minutes?
* What did the previous day look like before those days?
* Was there a gap up or gap down?
* Did the move break the first 15-minute high or low?
* How much did the ATM premium move in the same period?
* How quickly did the premium peak?
* How much of the premium move was given back after the peak?
* What conditions best predicted these high-expansion mornings?
* What exit logic captured the most of the move without trying to predict the exact top?

---

## Trading interpretation

Model this as **three separate problems**:

### 1. Entry detection

Identify the opening conditions that indicate a high-probability expansion day.

### 2. Expansion capture

Measure the premium velocity and whether the ATM option is expanding fast enough to matter.

### 3. Exit optimization

Estimate the best way to capture most of the move without trying to perfectly time the peak.

---

## Definitions to encode

Use these definitions unless the repo already has better ones. If better definitions exist, align to them but keep the same intent.

### Opening range

* The first 15 minutes of the trading session, from `09:15` to `09:30`.

### Aggressive underlying move

A day where NIFTY:

* breaks the first 15-minute high or low,
* continues in that direction,
* and produces a meaningful move in points within the first 15 minutes.

You must make this definition configurable so it can be tuned during research.

### ATM option move

For the ATM CE or PE contract of that day:

* record open, high, low, close,
* compute max gain percentage,
* compute time to peak,
* compute drawdown from peak,
* compute how much move is retained by candidate exits.

### Capture efficiency

For any exit rule:

`capture_efficiency = (exit_price - entry_price) / (peak_price - entry_price)` for longs

or the mirrored version for shorts if needed.

This metric is critical. Do not skip it.

---

## Data requirements

Build the research pipeline around these inputs:

### Underlying

* NIFTY 1m OHLCV
* NIFTY 15m OHLCV

### Option data

* ATM CE 1m OHLCV
* ATM PE 1m OHLCV
* Relevant strike for the day based on the system’s ATM selection logic
* If multiple ATM definitions exist, support a pluggable selection method

### Context features

* Previous day high/low/close
* Previous day range
* Previous day trend direction
* Gap up/down percentage
* Opening range width
* VWAP location
* Volume expansion
* ATR
* ADX
* RSI
* EMA stack / trend state if available
* Opening candle body and wick proportions
* Time of breakout
* Underlying-to-premium elasticity
* Premium velocity / acceleration
* Premium retracement after peak

---

## What to build

Implement the following modules cleanly and separately.

### 1. Data ingestion layer

* Pull historical data for the lookback period.
* Normalize timestamps to Indian market time.
* Handle missing candles gracefully.
* Cache or persist raw data to avoid repeated API calls.
* Make the lookback configurable, defaulting to 90 trading days for initial tests.

### 2. Feature extraction layer

For each trading day, compute:

* previous day context,
* gap context,
* first 1m/3m/5m/15m behavior,
* opening range metrics,
* breakout direction,
* premium expansion metrics,
* premium decay metrics,
* time-to-peak,
* capture-efficiency metrics.

### 3. Day classification layer

Classify each day into categories such as:

* trend morning,
* expansion morning,
* fakeout morning,
* range morning,
* low-volatility morning,
* failed breakout day.

Make the classification rule-based first, then leave space for later statistical labeling.

### 4. Research engine

Compute conditional probabilities such as:

* `P(ATM CE > 50% in first 15m | gap up, strong opening volume, breakout above first 15m high)`
* `P(ATM PE > 50% in first 15m | gap down, below VWAP, breakdown below first 15m low)`
* `P(premium gives back > 25% after peak | strong expansion day)`
* `P(exit rule A captures > 80% of MFE)`

### 5. Exit research engine

Evaluate multiple exit candidates, such as:

* fixed percentage trailing stop,
* underlying-based trailing stop,
* premium EMA-based exit,
* premium momentum decay exit,
* VWAP / EMA / Supertrend confirmation exit,
* hybrid exit combining premium and underlying signals.

For each exit rule, measure:

* average capture of MFE,
* average giveback,
* win rate,
* false exit rate,
* time in trade,
* stability across days.

### 6. Reporting layer

Generate human-readable output in:

* JSON,
* CSV,
* console summary.

The report should include:

* total trading days analyzed,
* number of high-expansion days,
* breakout direction split,
* ATM CE / PE max move distributions,
* average time to peak,
* average retracement after peak,
* best-performing entry conditions,
* best-performing exit rules.

### 7. Verification layer

Add tests to ensure:

* candles are aligned correctly,
* first 15-minute windows are correct,
* premium metrics are correct,
* breakout labels are correct,
* exit capture math is correct,
* no lookahead bias is introduced,
* missing data does not silently corrupt results.

---

## Important constraints

### No hindsight leakage

Do not use future data to label the entry decision. Every feature used for entry must be available at that timestamp in real time.

### No fake precision

If a peak cannot be identified exactly in live trading, do not pretend it can. Research the closest practical exit logic.

### Separate underlying and option logic

Do not assume underlying movement and option movement are identical. The option premium itself is a tradable instrument and must be treated as such.

### Make assumptions explicit

If ATM selection, session cutoffs, or breakout definitions are ambiguous, implement them as configurable options rather than hardcoding them.

---

## Suggested architecture

If the repository supports it, organize the research code like this:

* `app/services/research/`
* `lib/research/`
* `spec/research/`
* `data/research/`

Suggested service names:

* `Research::MarketDataFetcher`
* `Research::OpeningRangeAnalyzer`
* `Research::OptionExpansionAnalyzer`
* `Research::ExitCaptureAnalyzer`
* `Research::DayClassifier`
* `Research::ResearchReportGenerator`

If the codebase is not Rails-based in that section, adapt the structure to the existing conventions, but keep the separation of concerns.

---

## Deliverables

You must produce:

1. The full implementation of the research pipeline.
2. A runnable backtest or research script.
3. A clean summary report for the analyzed period.
4. Tests for the critical calculations.
5. Documentation explaining:

   * how to run the research,
   * how the day labels work,
   * how the exit capture metrics are computed,
   * how to extend the system.

---

## Output expectations

At the end, provide:

* the files changed,
* what each file does,
* how to run the research,
* sample output format,
* known limitations,
* next improvements.

---

## Acceptance criteria

Do not stop until all of these are true:

* I can run the research against historical data.
* I can see daily and aggregate statistics.
* I can identify the days where the underlying aggressively moved in the first 15 minutes.
* I can see how much the ATM premium moved on those days.
* I can see how much of that premium move each exit rule would have captured.
* I can compare entry and exit rules on the same historical dataset.
* Tests pass.
* The implementation is reproducible and does not rely on hidden manual steps.

---

## Working style

* Think like a quant researcher and a systems engineer.
* Be precise.
* Be skeptical of your own assumptions.
* Prefer simple, testable logic first.
* If something cannot be verified, flag it clearly instead of inventing certainty.
* If you need to inspect the repository structure first, do that, then implement.

Start by scanning the repository, identifying the existing DhanHQ integration, locating any data models or services related to market data, and then implement the research pipeline in the least disruptive way.

---

If you want, I can also turn this into a **Claude Code version with explicit step-by-step commands**, or a **shorter version optimized for maximum execution speed**.
Paste this into **Claude Code**:

---

You are working inside the `AlgoScalperApi` repository.

Your task is to **design, implement, verify, and document a full research engine** for detecting and analyzing **aggressive first-15-minute NIFTY moves** and the corresponding **ATM option premium expansion and decay**.

This is not a toy script. Treat it like a quant-research + trading-systems build.

## Non-negotiable objective

Build a system that can:

1. Pull historical OHLCV data for NIFTY and ATM option contracts.
2. Detect days where the **underlying moves aggressively in the first 15 minutes**.
3. Measure how much the **ATM CE/PE premium** expands during that same first-15-minute window.
4. Measure premium decay after the peak so we understand how much of the move can realistically be captured.
5. Derive statistical rules and entry/exit conditions from historical evidence.
6. Verify everything with reproducible backtests and tests.
7. Produce clean research outputs.

---

## What you must answer

Your code and research must answer these questions:

* On which days did NIFTY make a strong directional move in the first 15 minutes?
* What did the previous day look like before those days?
* Was there a gap up or gap down?
* Did the move break the first 15-minute high or low?
* How much did the ATM premium move in the same period?
* How quickly did the premium peak?
* How much of the premium move was given back after the peak?
* What conditions best predicted these high-expansion mornings?
* What exit logic captured the most of the move without trying to predict the exact top?

---

## How to think about this

Model the problem as **three separate research problems**:

### 1. Entry detection

Identify the opening conditions that indicate a high-probability expansion day.

### 2. Expansion capture

Measure premium velocity and determine whether the ATM option is expanding fast enough to matter.

### 3. Exit optimization

Estimate the best way to capture most of the move without trying to perfectly time the peak.

---

## Definitions to use

Use these definitions unless the repo already has a better implementation. If there is a better one, align to it but keep the same intent.

### Opening range

* The first 15 minutes of the trading session, from `09:15` to `09:30`.

### Aggressive underlying move

A day where NIFTY:

* breaks the first 15-minute high or low,
* continues in that direction,
* and produces a meaningful move in points within the first 15 minutes.

Make this configurable.

### ATM option move

For the ATM CE or PE contract of that day:

* record open, high, low, close,
* compute max gain percentage,
* compute time to peak,
* compute drawdown from peak,
* compute how much move is retained by candidate exits.

### Capture efficiency

For any exit rule:

`capture_efficiency = (exit_price - entry_price) / (peak_price - entry_price)` for longs

Mirror this for shorts if needed.

This metric is critical.

---

## Data requirements

Build the research pipeline around these inputs:

### Underlying

* NIFTY 1m OHLCV
* NIFTY 15m OHLCV

### Option data

* ATM CE 1m OHLCV
* ATM PE 1m OHLCV
* Relevant strike for the day based on the system’s ATM selection logic
* If multiple ATM definitions exist, support a pluggable selection method

### Context features

* Previous day high / low / close
* Previous day range
* Previous day trend direction
* Gap up / down percentage
* Opening range width
* VWAP location
* Volume expansion
* ATR
* ADX
* RSI
* EMA stack / trend state if available
* Opening candle body and wick proportions
* Time of breakout
* Underlying-to-premium elasticity
* Premium velocity / acceleration
* Premium retracement after peak

---

## What to build

Implement the following modules separately and clearly.

### 1. Data ingestion layer

* Pull historical data for the lookback period.
* Normalize timestamps to Indian market time.
* Handle missing candles gracefully.
* Cache or persist raw data to avoid repeated API calls.
* Make the lookback configurable, default to 90 trading days for initial tests.

### 2. Feature extraction layer

For each trading day, compute:

* previous day context,
* gap context,
* first 1m / 3m / 5m / 15m behavior,
* opening range metrics,
* breakout direction,
* premium expansion metrics,
* premium decay metrics,
* time-to-peak,
* capture-efficiency metrics.

### 3. Day classification layer

Classify each day into categories such as:

* trend morning,
* expansion morning,
* fakeout morning,
* range morning,
* low-volatility morning,
* failed breakout day.

Make this rule-based first, with room for later statistical labeling.

### 4. Research engine

Compute conditional probabilities such as:

* `P(ATM CE > 50% in first 15m | gap up, strong opening volume, breakout above first 15m high)`
* `P(ATM PE > 50% in first 15m | gap down, below VWAP, breakdown below first 15m low)`
* `P(premium gives back > 25% after peak | strong expansion day)`
* `P(exit rule A captures > 80% of MFE)`

### 5. Exit research engine

Evaluate multiple exit candidates, such as:

* fixed percentage trailing stop,
* underlying-based trailing stop,
* premium EMA-based exit,
* premium momentum decay exit,
* VWAP / EMA / Supertrend confirmation exit,
* hybrid exit combining premium and underlying signals.

For each exit rule, measure:

* average capture of MFE,
* average giveback,
* win rate,
* false exit rate,
* time in trade,
* stability across days.

### 6. Reporting layer

Generate outputs in:

* JSON,
* CSV,
* console summary.

The report should include:

* total trading days analyzed,
* number of high-expansion days,
* breakout direction split,
* ATM CE / PE max move distributions,
* average time to peak,
* average retracement after peak,
* best-performing entry conditions,
* best-performing exit rules.

### 7. Verification layer

Add tests to ensure:

* candles are aligned correctly,
* first 15-minute windows are correct,
* premium metrics are correct,
* breakout labels are correct,
* exit capture math is correct,
* no lookahead bias is introduced,
* missing data does not silently corrupt results.

---

## Important constraints

### No hindsight leakage

Do not use future data to label the entry decision. Every feature used for entry must be available at that timestamp in real time.

### No fake precision

If a peak cannot be identified exactly in live trading, do not pretend it can be. Research the closest practical exit logic.

### Separate underlying and option logic

Do not assume underlying movement and option movement are identical. The option premium itself is a tradable instrument and must be treated as such.

### Make assumptions explicit

If ATM selection, session cutoffs, or breakout definitions are ambiguous, implement them as configurable options rather than hardcoding them.

---

## Suggested architecture

If the repository supports it, organize the research code like this:

* `app/services/research/`
* `lib/research/`
* `spec/research/`
* `data/research/`

Suggested service names:

* `Research::MarketDataFetcher`
* `Research::OpeningRangeAnalyzer`
* `Research::OptionExpansionAnalyzer`
* `Research::ExitCaptureAnalyzer`
* `Research::DayClassifier`
* `Research::ResearchReportGenerator`

If the codebase is not Rails-based in that section, adapt the structure to the existing conventions, but keep the separation of concerns.

---

## Step-by-step execution plan

### Step 1 — Inspect the repository

Do this first.

* Identify the app structure.
* Find any existing DhanHQ integration.
* Find any market data services, models, jobs, or research scripts.
* Find existing test patterns.
* Find existing conventions for logging, config, persistence, and report generation.

Do not write code before this scan.

### Step 2 — Map the data flow

After inspection, write down the exact flow you will implement:

* historical data source,
* caching/persistence,
* feature extraction,
* classification,
* reporting,
* testing.

### Step 3 — Implement the data fetcher

Build the service that retrieves historical data and normalizes it.

### Step 4 — Implement the feature engine

Build the logic that computes all daily features and labels.

### Step 5 — Implement the expansion and decay metrics

Compute peak premium, time to peak, retracement, capture efficiency, and related stats.

### Step 6 — Implement exit simulation

Test multiple exit strategies against historical data.

### Step 7 — Implement the report generator

Generate daily and aggregate research summaries.

### Step 8 — Add tests

Write tests for:

* date/time boundaries,
* first-15-minute window logic,
* premium peak calculations,
* capture-efficiency formulas,
* classification rules,
* exit simulations.

### Step 9 — Run the full research

Run the pipeline on the configured historical window.

### Step 10 — Validate results

Check:

* obvious anomalies,
* missing data,
* lookahead bias,
* inconsistent strike selection,
* impossible premium values.

### Step 11 — Document everything

Update README or add a research doc explaining:

* what the system does,
* how to run it,
* what the outputs mean,
* what assumptions were made,
* where to extend it.

---

## Deliverables

You must produce:

1. The full implementation of the research pipeline.
2. A runnable backtest or research script.
3. A clean summary report for the analyzed period.
4. Tests for the critical calculations.
5. Documentation explaining:

   * how to run the research,
   * how the day labels work,
   * how the exit capture metrics are computed,
   * how to extend the system.

---

## Output expectations

At the end, provide:

* files changed,
* what each file does,
* how to run the research,
* sample output format,
* known limitations,
* next improvements.

---

## Acceptance criteria

Do not stop until all of these are true:

* The research can run against historical data.
* Daily and aggregate statistics are visible.
* The system can identify days where the underlying aggressively moved in the first 15 minutes.
* The system can show how much the ATM premium moved on those days.
* The system can show how much of that premium move each exit rule would have captured.
* The system can compare entry and exit rules on the same historical dataset.
* Tests pass.
* The implementation is reproducible and does not rely on hidden manual steps.

---

## Working style

* Think like a quant researcher and a systems engineer.
* Be precise.
* Be skeptical of your own assumptions.
* Prefer simple, testable logic first.
* If something cannot be verified, flag it clearly instead of inventing certainty.
* If you need to inspect the repository structure first, do that, then implement.

Begin by scanning the repository, identifying the existing DhanHQ integration, locating any data models or services related to market data, and then implement the research pipeline in the least disruptive way.

---

## Final instruction

If there is any ambiguity in ATM strike selection, session boundaries, or breakout rules, make them configurable and document the defaults clearly.
