---
name: inline_review_comment_generator
description: Generate GitHub-style inline code review comments with file, line, severity, issue, and suggestion
tags: [review, github, inline, comments, automation]
applies_to: [all]
severity: [info, warning, major, critical]
---

## Goal

Generate precise, actionable inline review comments in a structured format
suitable for posting as GitHub PR review comments. Each comment must be
self-contained, specific, and include a concrete suggestion.

## Output Format

```yaml
- file: path/to/file.rb
  line: LINE_NUMBER
  severity: info|warning|major|critical
  comment: |
    Clear explanation of the problem and why it matters.
  suggestion: |
    ```ruby
    # Concrete code showing the fix
    ```
```

## Severity Levels

| Severity | Meaning | Action |
|----------|---------|--------|
| `critical` | Bug, security issue, data loss risk | Block merge |
| `major` | Design violation, performance risk, broken contract | Should fix |
| `warning` | Style, idiom, minor design issue | Nice to fix |
| `info` | Observation, education, alternative approach | Optional |

## Comment Quality Rules

1. **Be specific.** Reference the exact variable/method name, not "this code".
2. **Explain the why.** Don't just say "use `find` instead of `select.first`" —
   say "use `find` instead of `select.first` because `find` short-circuits at
   the first match instead of collecting all matching elements into an array."
3. **Show the fix.** Always include a code block with the suggested change.
4. **One issue per comment.** Don't bundle 3 issues into one comment.
5. **Acknowledge tradeoffs.** If the fix has a tradeoff, mention it briefly.

## Examples

### N+1 Query

```yaml
- file: app/services/live/pnl_updater_service.rb
  line: 87
  severity: critical
  comment: |
    This loop calls `tracker.instrument` on each iteration, triggering one
    SQL query per tracker (N+1). With 20 active positions, this fires 20
    additional queries on every PnL tick (250ms interval = 4,800 extra queries/minute).
  suggestion: |
    ```ruby
    # Before
    active_trackers.each do |tracker|
      symbol = tracker.instrument.symbol_name
    end

    # After — load all instruments in one query
    active_trackers.includes(:instrument).each do |tracker|
      symbol = tracker.instrument.symbol_name
    end
    ```
```

### Thread Safety Violation

```yaml
- file: app/services/live/market_feed_hub.rb
  line: 213
  severity: critical
  comment: |
    `@subscriptions[security_id] = tracker` is a non-atomic write on a shared
    mutable hash accessed from multiple threads (tick handler thread + service
    threads). This can cause data races or lost updates under concurrent access.
  suggestion: |
    ```ruby
    # Use a Concurrent::Hash from the concurrent-ruby gem (already in Gemfile),
    # or protect with a Mutex:
    @subscriptions_mutex.synchronize { @subscriptions[security_id] = tracker }

    # Or replace with a thread-safe concurrent hash:
    @subscriptions = Concurrent::Hash.new
    ```
```

### Stale Config Mutation

```yaml
- file: app/services/signal/engine.rb
  line: 248
  severity: major
  comment: |
    `signals_cfg[:validation_mode] = 'conservative'` mutates the AlgoConfig
    result, which is a shared 30-second cache. This will corrupt the validation
    mode for all subsequent calls within the cache window, potentially affecting
    SENSEX signal generation while NIFTY is being processed.
  suggestion: |
    ```ruby
    # Use a local variable instead of mutating the shared config
    effective_validation_mode = ranging_market? ? 'conservative' : signals_cfg[:validation_mode]
    ```
```

### Missing Guard Clause

```yaml
- file: app/services/options/chain_analyzer.rb
  line: 443
  severity: warning
  comment: |
    The entire method body is wrapped in `if filtered.any?`. This buries the
    happy path and adds unnecessary indentation. A guard clause at the top
    makes the "do nothing" case explicit.
  suggestion: |
    ```ruby
    def score_strikes(filtered, atm_strike, option_type)
      return [] unless filtered.any?
      # ... rest of method at zero extra indentation
    end
    ```
```

### Non-idiomatic Ruby

```yaml
- file: app/services/optimization/indicator_optimizer.rb
  line: 67
  severity: info
  comment: |
    `scores.select { |s| s[:valid] }.first` traverses the entire array to
    collect all valid scores before taking the first. `find` stops at the
    first match, which is O(1) in the average case vs O(n) here.
  suggestion: |
    ```ruby
    # Before
    best = scores.select { |s| s[:valid] }.first

    # After
    best = scores.find { |s| s[:valid] }
    ```
```

## Batch Review Output

When reviewing a full file or PR, produce comments in a single YAML list:

```yaml
review_comments:
  - file: ...
    line: ...
    severity: critical
    comment: ...
    suggestion: ...
  - file: ...
    line: ...
    severity: major
    ...

summary:
  critical: 1
  major: 3
  warning: 5
  info: 2
  overall: "The core logic is sound. Critical thread-safety issue must be fixed before merge."
```

## Agent Instructions

1. Read the code carefully before generating any comments.
2. Number each finding by severity — output critical first.
3. Do not generate duplicate comments for the same pattern across lines.
4. If the same issue appears 5+ times, generate one comment with the
   canonical fix and note "this pattern appears N times in the file."
5. Never generate a comment without a concrete code suggestion.
