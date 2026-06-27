# Milestone 11.3: Continuous Improvement Loop

**Phase:** 11 — Live Trading & Operations  
**Goal:** System that improves from every trading session.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Implement DailyReviewJob
- [ ] Create `app/jobs/daily_review_job.rb`
- [ ] Schedule: 16:00 daily (after market close)
- [ ] Steps:
  1. Fetch all trades for the day
  2. Run LearningEngine analysis
  3. Generate PerformanceEngine report
  4. Run StrategyResearcherAgent on day's trades
  5. Compile daily summary report
  6. Store in `daily_reviews` table
  7. Send via Telegram/Email
- [ ] Output: daily P&L, win rate, best/worst trades, regime performance, AI insights

### 2. Add TradeClustering
- [ ] Create `app/services/trade_clustering.rb`
- [ ] Cluster trades by: regime, structure, time, delta, IV rank
- [ ] Algorithm: K-means on feature vectors (or DBSCAN)
- [ ] Identify: profitable clusters, losing clusters
- [ ] Cluster stability: track cluster membership over time
- [ ] Output: cluster profiles with stats (win rate, expectancy, count)

### 3. Create StrategyOptimizer
- [ ] Create `app/services/strategy_optimizer.rb`
- [ ] Optimize per-strategy parameters:
  - ORB: OR minutes, volume multiplier, target/stop multiples
  - Trend: EMA periods, ADX threshold, pullback depth
  - All: position sizing method, risk per trade
- [ ] Method: walk-forward optimization (rolling windows)
- [ ] Constraints: minimum trades, statistical significance
- [ ] Output: parameter recommendations with confidence
- [ ] Safety: only suggest, require manual approval to apply

### 4. Implement FeatureImportanceAnalyzer
- [ ] Create `app/services/feature_importance_analyzer.rb`
- [ ] Use: permutation importance, SHAP values (if ML), correlation
- [ ] Input: trade features at entry vs outcome (R-multiple)
- [ ] Output: ranked features by predictive power
- [ ] Per strategy, per regime
- [ ] Action: drop low-importance features, engineer new ones

### 5. Add RegimeAdaptation
- [ ] Create `app/services/regime_adaptation.rb`
- [ ] Track strategy performance by regime
- [ ] Adaptive weights: increase weight in favorable regimes, decrease in unfavorable
- [ ] Regime-specific parameters: e.g., wider stops in expanding volatility
- [ ] Transition smoothing: gradual weight changes
- [ ] Output: regime-adjusted strategy weights and parameters

### 6. Create StrikeSelectionOptimizer
- [ ] Create `app/services/strike_selection_optimizer.rb`
- [ ] Analyze historical strike performance:
  - By delta bucket, IV rank, DTE, regime
  - Win rate, expectancy, MFE/MAE by strike
- [ ] Optimize StrikeScorer weights per regime
- [ ] Dynamic ATM range: wider in high vol, tighter in low vol
- [ ] Output: updated scorer weights, strike selection rules

### 7. Implement RiskParameterTuning
- [ ] Create `app/services/risk_parameter_tuner.rb`
- [ ] Analyze drawdowns vs risk limits
- [ ] Optimize: daily loss limit, position size, max positions
- [ ] Kelly fraction calibration from actual win rate / RR
- [ ] Monte Carlo simulation for tail risk
- [ ] Output: risk limit recommendations with confidence intervals

### 8. Add AIPromptOptimization
- [ ] Create `app/services/ai_prompt_optimizer.rb`
- [ ] Track: agent output quality vs trade outcomes
- [ ] A/B test prompt variants (prompt versioning)
- [ ] Optimize: few-shot examples, instructions, output format
- [ ] Feedback loop: TradeReviewerAgent scores → prompt adjustment
- [ ] Version control: prompts in git, track performance per version

### 9. Create WeeklyRetrospectiveGenerator
- [ ] Create `app/services/weekly_retrospective_generator.rb`
- [ ] Schedule: Monday 8:00 AM
- [ ] Sections:
  - Performance summary (P&L, win rate, expectancy)
  - Strategy breakdown
  - Regime analysis
  - Execution quality (slippage, fill rate)
  - AI insights summary
  - Top 3 improvements for next week
  - Risk incidents
- [ ] Format: Markdown + JSON for dashboard
- [ ] Distribution: Telegram, Email, Confluence/wiki

### 10. Implement MonthlyStrategyReview
- [ ] Create `app/services/monthly_strategy_review.rb`
- [ ] Schedule: 1st of month, 9:00 AM
- [ ] Deep dive:
  - Statistical significance of strategy changes
  - Regime regime performance stability
  - Parameter drift detection
  - Correlation between strategies
  - Capacity analysis (slippage vs size)
  - New strategy ideas from research agent
- [ ] Output: strategy review document
- [ ] Action items: parameter changes, strategy enable/disable, new research

### 11. Add BacktestAutomation
- [ ] Create `app/services/backtest_automation.rb`
- [ ] Trigger: on strategy parameter change, new strategy added
- [ ] Pipeline:
  1. Fetch historical data (last 2 years)
  2. Run StrategyBacktestRunner
  3. Compare: new params vs current vs baseline
  4. Statistical tests (t-test, bootstrap)
  5. Generate backtest report
  6. Gate: must pass criteria to deploy
- [ ] Criteria: expectancy > 0, Sharpe > 1, max DD < 10%, min 100 trades

### 12. Document Continuous Improvement Process
- [ ] Create `docs/continuous_improvement.md` with:
  - Improvement loop diagram
  - Daily/weekly/monthly cadence
  - Decision gates (what requires approval)
  - Experiment framework (A/B testing strategies)
  - Version control for strategies, prompts, parameters
  - Rollback procedures
  - Success metrics for improvements
  - Innovation budget (time for research)

---

## Acceptance Criteria
- [ ] Daily review runs automatically at 16:00
- [ ] Trade clustering identifies actionable patterns
- [ ] Strategy optimizer suggests valid improvements
- [ ] Feature importance guides engineering effort
- [ ] Regime adaptation improves regime-specific performance
- [ ] Strike optimizer improves strike selection win rate
- [ ] Risk tuning reduces drawdown without killing returns
- [ ] Prompt optimization improves AI agent quality scores
- [ ] Weekly retrospective delivered every Monday
- [ ] Monthly review drives strategic decisions
- [ ] Backtest automation gates all strategy changes
- [ ] Process documented and followed

---

## Notes
- Improvement loop is the COMPETITIVE ADVANTAGE
- Automate everything possible; human review for approval
- Track "improvement velocity": changes deployed per month
- Balance: exploit current edge vs explore new edges
- Guardrails: never auto-deploy without backtest gate
- Celebrate: document wins from improvements
- Culture: blameless post-mortems on losses