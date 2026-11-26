# Derivation of the profit-share cap

The holdout test asks whether one session supplies more of the holdout's profit than it should. The cap it uses is derived,
not chosen. It replaces the 25% that was first proposed, which was a judgment rather than a derivation.

## The statistic

Let the holdout's winning sessions have net R totals `x_1 … x_W`, all positive. The statistic is `S = max(x) / sum(x)`, the
share of positive net R that the largest winning session supplies. A result passes when `S` does not exceed the cap.

## The null

The cap is the threshold above which `S` would be surprising if no session were special. The null is that the `W` winning
sessions are exchangeable draws from one distribution, truncated to positive, with no outlier.

Each parameter of that distribution is taken from the holdout's own winners, and each is chosen so that the outlier under test
cannot move the threshold:

- **Location:** the median of the winning sessions. The mean would be pulled by the very session being tested.
- **Spread:** `1.4826 × MAD`, the scaled median absolute deviation. A standard deviation would grow with the outlier and
  weaken the test. The constant 1.4826 makes the MAD consistent with a normal standard deviation.

## The cap

Simulate `B = 10,000` holdouts with `W` winners drawn from that null, record the largest share in each, and take the
`(1 − α)` quantile, with `α = 0.05`. The simulation uses a fixed seed, so the same holdout always gets the same cap.

If the spread is zero, every winner is equal, so the only fair share is `1/W`. The cap is then `1/W`, and any unequal
winner is an outlier.

## What depends on what

The cap depends on two things the holdout supplies: how many sessions won, and how dispersed their profits are. It does not
depend on the mean, the trade count, or the total profit. A holdout with consistent winners gets a tight cap. One with widely
varying winners gets a looser cap, because a large winner is then within the range the winners themselves allow.

Simulated caps, at median 1, for each winner count `W` and relative spread (spread ÷ median), with seed 19:

| W | fair share 1/W | spread 0 | 0.25 | 0.5 | 0.75 | 1.0 |
| --- | --- | --- | --- | --- | --- | --- |
| 10 | 10.0% | 10.0% | 16.3% | 22.3% | 26.0% | 28.0% |
| 15 | 6.7% | 6.7% | 11.1% | 15.3% | 18.0% | 19.4% |
| 20 | 5.0% | 5.0% | 8.4% | 11.7% | 13.8% | 15.0% |
| 30 | 3.3% | 3.3% | 5.8% | 8.0% | 9.5% | 10.3% |

Read against the old fixed 25%: for 15 winners with moderate spread (0.25) the derived cap is 11%, so a 25% cap would have
let a single session carry more than twice what the test allows. Only a very dispersed holdout with ten winners reaches 25%.

## Assumptions to review

These are judgments, and they are the parts that a reviewer should change if they disagree:

1. **Normal shape** for the truncated null. The real winning sessions are not guaranteed to be normal. A heavier tail would
   raise the cap, so the normal shape is the stricter choice for a tight holdout and the looser one for a fat-tailed one.
2. **`α = 0.05`.** A holdout with no special session exceeds its cap about 5% of the time by construction. That is a false
   rejection rate, not a measure of edge, so it is stated as a choice.
3. **Exchangeable winners.** Winners on different days can differ for reasons that are not luck, such as regime. The test
   does not model that. It only asks whether one session stands apart from the others.

## What this does not establish

The cap says whether one session dominates. It does not say whether the edge is real. The confidence interval, the
pre-registered hypothesis and the cost stress still decide that. The eligibility floors (30 trades and 30 sessions) are
floors, not significance.

## Reproducing the table

`simulatedDominanceCap(W, 1, spread, 19)` in `src/research/stats.ts` produces each entry. `tests/timeMachine.test.ts` pins the
properties the table depends on: zero spread gives `1/W`, the cap widens with spread, and it falls with more winners.
