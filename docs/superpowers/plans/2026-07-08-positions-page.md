# Positions Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a standalone `/positions` dashboard page listing open + closed positions with filters, and a slide-over detail drawer showing a single position's full trade lifecycle (entry context, PnL, exit reason, and — when the position came from the strategy platform — its guard-decision trail).

**Architecture:** Backend adds one read endpoint (`GET /api/positions/:id`) and a `Positions::Serializer.detail` method that layers entry/exit/strategy detail on top of the existing `open`/`closed` serializers. Frontend adds one route (`/positions`), one store (`usePositionDetail`), a list view reusing existing `Table`/`PositionRow`-style primitives, and a `PositionDetailDrawer` component. No changes to the existing Dashboard `OpenPositions` widget.

**Tech Stack:** Rails 8 API (RSpec, FactoryBot), Solid.js frontend (Vite, existing `apiClient`/`endpoints`/`cable` modules), Tailwind utility classes matching existing dashboard styling.

## Global Constraints

- Backend changes are confined to `app/controllers/api/positions_controller.rb`, `app/services/positions/serializer.rb`, and `config/routes.rb` — no changes to locked/infra layers per project CLAUDE.md (positions serialization/API is not in the LOCKED list; `PositionTracker` model itself is not modified).
- `authenticate_dashboard_token!` gate must be applied to the new `show` action exactly as `index` already does.
- No new frontend test framework — this repo has no Solid component test harness; skip frontend tests, cover behavior via backend request specs plus manual verification.
- Follow existing code patterns: `apiClient`/`endpoints` for new frontend data fetching (matches `useReports.js`/`useHoldings.js`), Tailwind classes matching `PositionRow.jsx`/`Reports.jsx` conventions, `Table`/`TableRow`/`TableCell` primitives from `src/components/ui/Table.jsx`.

---

### Task 1: `Positions::Serializer.detail` + backend unit spec

**Files:**
- Modify: `app/services/positions/serializer.rb`
- Test: `spec/services/positions/serializer_spec.rb` (new file — no existing spec for this module)

**Interfaces:**
- Consumes: `PositionTracker` model (existing columns: `iv_at_entry`, `vix_at_entry`, `dte_at_entry`, `atm_strike`, `expiry_date`, `entry_underlying_price`, `entry_tf`, `alpha_source`, `entry_path`, `signal_confidence`, `high_water_mark_pnl`, `hwm_pnl_pct`, `secured_sl_price`, `breakeven_locked`, `profit_zone_state`, `exit_reason`, `exit_path`, `execution` jsonb, `exited_at`, `meta` jsonb), `tracker.meta_snapshot` (`PositionMetaSnapshot`, has `config_snapshot`, `config_version_hash`), `Strategies::Signal` model (`belongs_to :position_tracker, optional: true`, has `strategy_record` (slug via `belongs_to :strategy_record`), `action`, `confidence`, `outcome`, `reason`, `metadata` jsonb with keys `"entry_result_reason"` and `"guard_results"`).
- Produces: `Positions::Serializer.detail(tracker)` → `Hash`. Used by Task 2's controller `show` action.

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/positions/serializer_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::Serializer do
  describe '.detail' do
    context 'when the position is open' do
      let(:tracker) do
        create(:position_tracker,
               iv_at_entry: 18.5, vix_at_entry: 13.2, dte_at_entry: 2,
               atm_strike: 25000, entry_underlying_price: 24980.5,
               entry_tf: '1m', alpha_source: 'supertrend_v1', entry_path: 'strategy_platform',
               signal_confidence: 0.7)
      end

      it 'includes base open fields plus entry context' do
        result = described_class.detail(tracker)

        expect(result[:id]).to eq(tracker.id)
        expect(result[:ltp]).to be_present # from base `open` serializer
        expect(result[:entry_context]).to eq(
          iv_at_entry: 18.5, vix_at_entry: 13.2, dte_at_entry: 2,
          atm_strike: 25000.0, expiry_date: nil,
          entry_underlying_price: 24980.5, entry_tf: '1m',
          alpha_source: 'supertrend_v1', entry_path: 'strategy_platform',
          signal_confidence: 0.7
        )
        expect(result[:exit_block]).to be_nil
      end

      it 'includes trailing/HWM state' do
        tracker.update!(hwm_pnl_pct: 0.18, secured_sl_price: BigDecimal('25100.0'),
                         breakeven_locked: true, profit_zone_state: 'tier_2')

        result = described_class.detail(tracker)
        expect(result[:trailing_state]).to eq(
          high_water_mark_pnl: tracker.high_water_mark_pnl.to_f,
          hwm_pnl_pct: 0.18,
          secured_sl_price: 25100.0,
          breakeven_locked: true,
          profit_zone_state: 'tier_2'
        )
      end

      it 'omits config_snapshot when no meta_snapshot exists' do
        result = described_class.detail(tracker)
        expect(result[:config_snapshot]).to be_nil
        expect(result[:config_version_hash]).to be_nil
      end

      it 'includes config_snapshot when a meta_snapshot exists' do
        tracker.create_meta_snapshot!(config_version_hash: 'abc123', config_snapshot: { risk: { max_loss: 500 } })

        result = described_class.detail(tracker)
        expect(result[:config_version_hash]).to eq('abc123')
        expect(result[:config_snapshot]).to eq(risk: { max_loss: 500 })
      end

      it 'includes the linked strategy signal and guard trail when present' do
        signal = create(:strategy_signal,
                         position_tracker: tracker,
                         action: 'buy_call',
                         confidence: 0.7,
                         outcome: 'executed',
                         reason: 'supertrend_bullish_adx_confirmed',
                         metadata: {
                           'entry_result_reason' => nil,
                           'guard_results' => [{ 'guard' => 'Entries::Guards::CooldownGuard', 'result' => 'pass' }]
                         })

        result = described_class.detail(tracker)
        expect(result[:strategy_signal]).to eq(
          strategy_slug: signal.strategy_record.slug,
          action: 'buy_call',
          confidence: 0.7,
          outcome: 'executed',
          reason: 'supertrend_bullish_adx_confirmed',
          entry_result_reason: nil,
          guard_results: [{ 'guard' => 'Entries::Guards::CooldownGuard', 'result' => 'pass' }]
        )
      end

      it 'sets strategy_signal to nil when no signal is linked' do
        result = described_class.detail(tracker)
        expect(result[:strategy_signal]).to be_nil
      end
    end

    context 'when the position is closed' do
      let(:tracker) do
        create(:position_tracker, :exited,
               exit_price: BigDecimal('27500.00'),
               exit_reason: 'profit_target_hit',
               exit_path: 'unified_exit_checker',
               exited_at: Time.current,
               execution: { 'classified_as' => 'winner' })
      end

      it 'includes base closed fields plus the exit block' do
        result = described_class.detail(tracker)

        expect(result[:exit_price]).to eq(27500.0) # from base `closed` serializer
        expect(result[:exit_block]).to eq(
          exit_reason: 'profit_target_hit',
          exit_path: 'unified_exit_checker',
          exit_classification: 'winner',
          exited_at: tracker.exited_at.iso8601
        )
      end
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/positions/serializer_spec.rb -f doc`
Expected: FAIL — `NoMethodError: undefined method 'detail' for Positions::Serializer`

- [ ] **Step 3: Implement `Positions::Serializer.detail`**

Add to `app/services/positions/serializer.rb` (inside `module Serializer`, alongside `open`/`closed`):

```ruby
    def detail(tracker)
      base = tracker.exited_at.present? ? closed(tracker) : open(tracker)

      base.merge(
        entry_context: entry_context(tracker),
        exit_block: exit_block(tracker),
        trailing_state: trailing_state(tracker),
        config_snapshot: tracker.meta_snapshot&.config_snapshot&.deep_symbolize_keys,
        config_version_hash: tracker.meta_snapshot&.config_version_hash,
        strategy_signal: strategy_signal_block(tracker),
        meta: tracker.meta
      )
    end

    def trailing_state(tracker)
      {
        high_water_mark_pnl: tracker.high_water_mark_pnl&.to_f,
        hwm_pnl_pct: tracker.hwm_pnl_pct&.to_f,
        secured_sl_price: tracker.secured_sl_price&.to_f,
        breakeven_locked: tracker.breakeven_locked,
        profit_zone_state: tracker.profit_zone_state
      }
    end

    def entry_context(tracker)
      {
        iv_at_entry: tracker.iv_at_entry&.to_f,
        vix_at_entry: tracker.vix_at_entry&.to_f,
        dte_at_entry: tracker.dte_at_entry,
        atm_strike: tracker.atm_strike&.to_f,
        expiry_date: tracker.expiry_date&.iso8601,
        entry_underlying_price: tracker.entry_underlying_price&.to_f,
        entry_tf: tracker.entry_tf,
        alpha_source: tracker.alpha_source,
        entry_path: tracker.entry_path,
        signal_confidence: tracker.signal_confidence&.to_f
      }
    end

    def exit_block(tracker)
      return nil unless tracker.exited_at.present?

      execution_meta = tracker.execution.is_a?(Hash) ? tracker.execution : {}
      {
        exit_reason: tracker.exit_reason,
        exit_path: tracker.exit_path,
        exit_classification: execution_meta['classified_as'],
        exited_at: tracker.exited_at&.iso8601
      }
    end

    def strategy_signal_block(tracker)
      signal = Strategies::Signal.find_by(position_tracker_id: tracker.id)
      return nil unless signal

      {
        strategy_slug: signal.strategy_record.slug,
        action: signal.action,
        confidence: signal.confidence&.to_f,
        outcome: signal.outcome,
        reason: signal.reason,
        entry_result_reason: signal.metadata['entry_result_reason'],
        guard_results: signal.metadata['guard_results']
      }
    end
```

Note: `entry_context` spec above expects float `signal_confidence: 0.7` — the `confidence` column in `strategy_signal_block` and `signal_confidence` column on `PositionTracker` are two different columns on two different models; don't conflate them when implementing.

- [ ] **Step 4: Run spec to verify it passes**

Run: `bundle exec rspec spec/services/positions/serializer_spec.rb -f doc`
Expected: PASS, all 6 examples green

- [ ] **Step 5: Commit**

```bash
git add app/services/positions/serializer.rb spec/services/positions/serializer_spec.rb
git commit -m "feat: add Positions::Serializer.detail for single-position view"
```

---

### Task 2: `GET /api/positions/:id` endpoint + request spec

**Files:**
- Modify: `app/controllers/api/positions_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/api/positions_controller_spec.rb`

**Interfaces:**
- Consumes: `Positions::Serializer.detail(tracker)` from Task 1.
- Produces: `GET /api/positions/:id` → `200 { <detail hash> }` or `404 { error: "not_found" }`. Consumed by Task 3's frontend store.

- [ ] **Step 1: Write the failing request specs**

Add to `spec/requests/api/positions_controller_spec.rb` (append inside the existing `RSpec.describe Api::PositionsController do ... end` block, after the `POST /api/positions/:id/close` describe block, before the final `end`):

```ruby
  describe 'GET /api/positions/:id' do
    it 'returns the serialized detail for an existing tracker' do
      tracker = create(:position_tracker)
      allow(Positions::Serializer).to receive(:detail).and_call_original

      get "/api/positions/#{tracker.id}"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['id']).to eq(tracker.id)
      expect(Positions::Serializer).to have_received(:detail).with(tracker)
    end

    it 'returns 404 for an unknown id' do
      get '/api/positions/999999'

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('not_found')
    end
  end
```

Note: the top-level `before` block in this spec file stubs `PositionTracker.active`/`exited` to return `PositionTracker.none` — that only affects `index`, not `find_by`/`find` used by `show`, so `create(:position_tracker)` + a direct lookup by id works unaffected.

- [ ] **Step 2: Run specs to verify they fail**

Run: `bundle exec rspec spec/requests/api/positions_controller_spec.rb -f doc`
Expected: FAIL — `GET /api/positions/:id` examples fail with routing error (`No route matches`)

- [ ] **Step 3: Add the route**

In `config/routes.rb`, find the existing line:

```ruby
    get :positions, to: "positions#index"
    post "positions/:id/close", to: "positions#close"
```

Change to:

```ruby
    get :positions, to: "positions#index"
    get "positions/:id", to: "positions#show"
    post "positions/:id/close", to: "positions#close"
```

- [ ] **Step 4: Add the `show` action**

In `app/controllers/api/positions_controller.rb`, add a `show` action after `index` and before `close`:

```ruby
    def show
      tracker = PositionTracker.includes(:watchable, :instrument, :meta_snapshot).find_by(id: params[:id])
      return render json: { error: "not_found" }, status: :not_found unless tracker

      render json: Positions::Serializer.detail(tracker)
    end
```

- [ ] **Step 5: Run specs to verify they pass**

Run: `bundle exec rspec spec/requests/api/positions_controller_spec.rb -f doc`
Expected: PASS, all examples green (existing + 2 new)

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/positions_controller.rb config/routes.rb spec/requests/api/positions_controller_spec.rb
git commit -m "feat: add GET /api/positions/:id detail endpoint"
```

---

### Task 3: Frontend endpoint + `usePositionDetail` store

**Files:**
- Modify: `dashboard/src/lib/api/endpoints.js`
- Create: `dashboard/src/stores/usePositionDetail.js`

**Interfaces:**
- Consumes: `apiClient` (axios-like, from `dashboard/src/lib/api/client.js` via `dashboard/src/lib/api/index.js`), `endpoints.positionDetail(id)` (new).
- Produces: `usePositionDetail()` → `{ detail, loading, error, fetchDetail(id) }` where `detail` is a Solid signal holding the raw response object (or `null`). Used by Task 5's `PositionDetailDrawer`.

- [ ] **Step 1: Add the endpoint**

In `dashboard/src/lib/api/endpoints.js`, change:

```js
  positions: '/positions',
  closePosition: (id) => `/positions/${id}/close`,
```

to:

```js
  positions: '/positions',
  positionDetail: (id) => `/positions/${id}`,
  closePosition: (id) => `/positions/${id}/close`,
```

- [ ] **Step 2: Create the store**

```js
// dashboard/src/stores/usePositionDetail.js
import { createSignal } from 'solid-js'
import { apiClient } from '../lib/api'
import { endpoints } from '../lib/api/endpoints'

export function usePositionDetail() {
  const [detail, setDetail] = createSignal(null)
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  async function fetchDetail(id) {
    if (id == null) return
    setLoading(true)
    setError(null)
    try {
      const res = await apiClient.get(endpoints.positionDetail(id))
      setDetail(res.data)
      return { ok: true }
    } catch (e) {
      setError(e.message)
      setDetail(null)
      return { ok: false, error: e.message }
    } finally {
      setLoading(false)
    }
  }

  function clear() {
    setDetail(null)
    setError(null)
  }

  return { detail, loading, error, fetchDetail, clear }
}
```

- [ ] **Step 3: Manual verification**

There is no frontend test harness in this repo (per Global Constraints) — verify by running the dev server and checking the network tab once Task 5 wires this store to a UI trigger. No standalone verification step for this task in isolation; it is exercised end-to-end in Task 5's manual verification step.

- [ ] **Step 4: Commit**

```bash
cd dashboard
git add src/lib/api/endpoints.js src/stores/usePositionDetail.js
git commit -m "feat: add usePositionDetail store and positionDetail endpoint"
```

---

### Task 4: `/positions` route + list page

**Files:**
- Create: `dashboard/src/views/Positions.jsx`
- Modify: `dashboard/src/App.jsx`
- Modify: `dashboard/src/lib/config/routes.js`

**Interfaces:**
- Consumes: `usePositions()` from `dashboard/src/stores/usePositions.js` (existing — returns `{ open, closed, fetchPositions, closeOpenPosition, closingPositionId }`), `Table`/`TableHeader`/`TableBody`/`TableRow`/`TableHead`/`TableCell` from `dashboard/src/components/ui/Table.jsx`, `AnimatedNumber` from `dashboard/src/components/AnimatedNumber.jsx`.
- Produces: `Positions` default export component, rendered at route `/positions`. Selecting a row calls `props.onSelectPosition(id)` — wired to the drawer in Task 5.

- [ ] **Step 1: Create the list page**

```jsx
// dashboard/src/views/Positions.jsx
import { For, Show, createMemo, createSignal, onMount } from 'solid-js'
import { usePositions } from '../stores/usePositions'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../components/ui/Table'
import AnimatedNumber from '../components/AnimatedNumber'
import PositionDetailDrawer from '../components/positions/PositionDetailDrawer'

export default function Positions() {
  const { open, closed, fetchPositions, closeOpenPosition, closingPositionId } = usePositions()
  const [tab, setTab] = createSignal('open')
  const [selectedId, setSelectedId] = createSignal(null)

  onMount(() => fetchPositions())

  const rows = createMemo(() => (tab() === 'open' ? open() : closed()))

  return (
    <div class="space-y-6">
      <div class="flex items-center gap-2">
        <button
          type="button"
          onClick={() => setTab('open')}
          class={`px-4 py-2 rounded-xl text-xs font-black uppercase tracking-wider transition-all ${
            tab() === 'open' ? 'bg-primary-600 text-white' : 'bg-white/[0.03] text-gray-400 hover:text-white'
          }`}
        >
          Open ({open().length})
        </button>
        <button
          type="button"
          onClick={() => setTab('closed')}
          class={`px-4 py-2 rounded-xl text-xs font-black uppercase tracking-wider transition-all ${
            tab() === 'closed' ? 'bg-primary-600 text-white' : 'bg-white/[0.03] text-gray-400 hover:text-white'
          }`}
        >
          Closed ({closed().length})
        </button>
      </div>

      <div class="bg-white/[0.01] border border-white/5 rounded-2xl overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Symbol</TableHead>
              <TableHead class="text-center">Side</TableHead>
              <TableHead class="text-right">Qty</TableHead>
              <TableHead class="text-right">Entry</TableHead>
              <TableHead class="text-right">{tab() === 'open' ? 'LTP' : 'Exit'}</TableHead>
              <TableHead class="text-right">PnL</TableHead>
              <TableHead class="text-right">PnL %</TableHead>
              <Show when={tab() === 'open'}><TableHead class="text-center">Action</TableHead></Show>
            </TableRow>
          </TableHeader>
          <TableBody>
            <For each={rows()}>
              {(pos) => (
                <TableRow clickable onClick={() => setSelectedId(pos.id)}>
                  <TableCell class="px-6 py-4 font-bold text-gray-100 uppercase text-sm">{pos.symbol}</TableCell>
                  <TableCell class="px-4 py-4 text-center">
                    <span class={`text-[9px] font-black px-3 py-1 rounded-full uppercase ${pos.side === 'BUY' ? 'bg-emerald-500/10 text-emerald-400' : 'bg-rose-500/10 text-rose-400'}`}>
                      {pos.side}
                    </span>
                  </TableCell>
                  <TableCell class="px-4 py-4 text-right text-gray-400"><AnimatedNumber value={pos.quantity} integer decimals={0} /></TableCell>
                  <TableCell class="px-4 py-4 text-right text-gray-500 text-xs"><AnimatedNumber value={pos.entry_price} decimals={2} /></TableCell>
                  <TableCell class="px-4 py-4 text-right text-white font-black">
                    <AnimatedNumber value={tab() === 'open' ? pos.ltp : pos.exit_price} decimals={2} />
                  </TableCell>
                  <TableCell class="px-4 py-4 text-right font-black"><AnimatedNumber value={pos.pnl} showSign currency absolute decimals={2} pnlColor /></TableCell>
                  <TableCell class="px-4 py-4 text-right font-bold"><AnimatedNumber value={pos.pnl_pct} showSign suffix="%" decimals={2} pnlColor /></TableCell>
                  <Show when={tab() === 'open'}>
                    <TableCell class="px-4 py-4 text-center">
                      <button
                        type="button"
                        class="text-[10px] font-black uppercase px-3 py-2 rounded-xl border border-rose-500/30 text-rose-300 bg-rose-500/10 hover:bg-rose-500/25 disabled:opacity-40"
                        disabled={closingPositionId() === pos.id}
                        onClick={(e) => { e.stopPropagation(); closeOpenPosition(pos.id) }}
                      >
                        {closingPositionId() === pos.id ? '…' : 'Close'}
                      </button>
                    </TableCell>
                  </Show>
                </TableRow>
              )}
            </For>
          </TableBody>
        </Table>
        <Show when={rows().length === 0}>
          <div class="py-16 text-center text-gray-500 text-sm">No {tab()} positions.</div>
        </Show>
      </div>

      <PositionDetailDrawer positionId={selectedId()} onClose={() => setSelectedId(null)} />
    </div>
  )
}
```

Note: `TableRow` in `dashboard/src/components/ui/Table.jsx` already supports a `clickable` prop for hover styling but does not currently forward `onClick` — Task 4 Step 1 code above passes `onClick` directly as a prop, which Solid.js forwards to the underlying `<tr>` automatically as a native DOM event handler regardless of whether `TableRow` explicitly destructures it, because Solid's `<tr {...props}>`-style spread is not used here — **verify this behavior manually in Step 3**; if `onClick` doesn't fire, add `onClick={props.onClick}` to the `<tr>` in `Table.jsx`'s `TableRow` (this is a one-line fallback fix, apply it if Step 3 fails).

- [ ] **Step 2: Wire the route**

In `dashboard/src/lib/config/routes.js`, change the existing placeholder Portfolio nav entry:

```js
      { id: 'positions', label: 'Positions', href: ROUTES.DASHBOARD, icon: 'positions' }, // Existing positions are on dashboard
```

to:

```js
      { id: 'positions', label: 'Positions', href: ROUTES.POSITIONS, icon: 'positions' },
```

In `dashboard/src/App.jsx`, add the lazy import near the other view imports:

```js
const Positions = lazy(() => import('./views/Positions'))
```

And add the route inside the `AppShell` route group, alongside the other portfolio-adjacent routes:

```jsx
          <Route path="/positions" component={Positions} />
```

- [ ] **Step 3: Manual verification**

Run: `cd dashboard && npm run dev`
Then in a browser: navigate to `/positions`, confirm the Open/Closed tabs render, the table lists positions (or the empty state if none), and clicking a row does not error in the console (the drawer component doesn't exist yet until Task 5, so temporarily comment out the `<PositionDetailDrawer />` line and the `selectedId`/`onClick` wiring if it errors on the missing import — restore both once Task 5 lands). If `onClick` doesn't fire on the row, apply the one-line `Table.jsx` fallback noted in Step 1.

- [ ] **Step 4: Commit**

```bash
cd dashboard
git add src/views/Positions.jsx src/App.jsx src/lib/config/routes.js
git commit -m "feat: add /positions list page with open/closed tabs"
```

---

### Task 5: `PositionDetailDrawer` component

**Files:**
- Create: `dashboard/src/components/positions/PositionDetailDrawer.jsx`

**Interfaces:**
- Consumes: `usePositionDetail()` from Task 3, `props.positionId` (number or `null`) and `props.onClose` (function) from Task 4's `Positions.jsx`.
- Produces: `PositionDetailDrawer` default export. No further consumers in this plan — it is the leaf UI component.

- [ ] **Step 1: Create the drawer**

```jsx
// dashboard/src/components/positions/PositionDetailDrawer.jsx
import { Show, createEffect, For } from 'solid-js'
import { usePositionDetail } from '../../stores/usePositionDetail'
import AnimatedNumber from '../AnimatedNumber'

function Field(props) {
  return (
    <div class="flex flex-col">
      <span class="text-[9px] text-gray-500 font-black uppercase tracking-wider mb-1">{props.label}</span>
      <span class="text-sm text-gray-200 font-bold">{props.value ?? '—'}</span>
    </div>
  )
}

export default function PositionDetailDrawer(props) {
  const { detail, loading, error, fetchDetail, clear } = usePositionDetail()

  createEffect(() => {
    const id = props.positionId
    if (id != null) fetchDetail(id)
    else clear()
  })

  function handleKeydown(e) {
    if (e.key === 'Escape') props.onClose()
  }

  return (
    <Show when={props.positionId != null}>
      <div class="fixed inset-0 z-50 flex justify-end" onKeyDown={handleKeydown}>
        <div class="fixed inset-0 bg-black/60" onClick={() => props.onClose()} />
        <div class="relative w-full max-w-md h-full bg-gray-900 border-l border-white/10 overflow-y-auto p-6 space-y-6">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-black text-white uppercase tracking-tight">Position Detail</h2>
            <button type="button" class="text-gray-400 hover:text-white text-xl leading-none" onClick={() => props.onClose()}>&times;</button>
          </div>

          <Show when={loading()}>
            <div class="text-center text-gray-500 text-sm py-10">Loading…</div>
          </Show>

          <Show when={error()}>
            <div class="text-center text-rose-400 text-sm py-10">Failed to load: {error()}</div>
          </Show>

          <Show when={detail() && !loading()}>
            {(d) => (
              <div class="space-y-6">
                <div class="flex items-center justify-between">
                  <div>
                    <div class="text-xl font-black text-white uppercase">{d().symbol}</div>
                    <div class="text-[10px] text-gray-500 uppercase tracking-wider">
                      {d().side} · Qty {d().quantity} · {d().paper ? 'Paper' : 'Live'}
                    </div>
                  </div>
                </div>

                <div class="grid grid-cols-2 gap-4 bg-white/[0.02] border border-white/5 rounded-xl p-4">
                  <Field label="Entry Price" value={<AnimatedNumber value={d().entry_price} decimals={2} />} />
                  <Field label={d().exit_price != null ? 'Exit Price' : 'LTP'} value={<AnimatedNumber value={d().exit_price ?? d().ltp} decimals={2} />} />
                  <Field label="PnL" value={<AnimatedNumber value={d().pnl} showSign currency absolute decimals={2} pnlColor />} />
                  <Field label="PnL %" value={<AnimatedNumber value={d().pnl_pct} showSign suffix="%" decimals={2} pnlColor />} />
                  <Field label="High Water Mark" value={<AnimatedNumber value={d().hwm_pnl} currency decimals={2} />} />
                </div>

                <div class="space-y-2">
                  <h3 class="text-[10px] text-gray-500 font-black uppercase tracking-widest">Trailing State</h3>
                  <div class="grid grid-cols-2 gap-4 bg-white/[0.02] border border-white/5 rounded-xl p-4">
                    <Field label="HWM PnL %" value={d().trailing_state?.hwm_pnl_pct} />
                    <Field label="Secured SL" value={d().trailing_state?.secured_sl_price} />
                    <Field label="Breakeven Locked" value={d().trailing_state?.breakeven_locked ? 'Yes' : 'No'} />
                    <Field label="Profit Zone" value={d().trailing_state?.profit_zone_state} />
                  </div>
                </div>

                <div class="space-y-2">
                  <h3 class="text-[10px] text-gray-500 font-black uppercase tracking-widest">Entry Context</h3>
                  <div class="grid grid-cols-2 gap-4 bg-white/[0.02] border border-white/5 rounded-xl p-4">
                    <Field label="IV at Entry" value={d().entry_context?.iv_at_entry} />
                    <Field label="VIX at Entry" value={d().entry_context?.vix_at_entry} />
                    <Field label="DTE at Entry" value={d().entry_context?.dte_at_entry} />
                    <Field label="ATM Strike" value={d().entry_context?.atm_strike} />
                    <Field label="Expiry" value={d().entry_context?.expiry_date} />
                    <Field label="Entry Timeframe" value={d().entry_context?.entry_tf} />
                    <Field label="Alpha Source" value={d().entry_context?.alpha_source} />
                    <Field label="Entry Path" value={d().entry_context?.entry_path} />
                  </div>
                </div>

                <Show when={d().exit_block}>
                  <div class="space-y-2">
                    <h3 class="text-[10px] text-gray-500 font-black uppercase tracking-widest">Exit</h3>
                    <div class="grid grid-cols-2 gap-4 bg-white/[0.02] border border-white/5 rounded-xl p-4">
                      <Field label="Reason" value={d().exit_block.exit_reason} />
                      <Field label="Path" value={d().exit_block.exit_path} />
                      <Field label="Classification" value={d().exit_block.exit_classification} />
                      <Field label="Exited At" value={d().exit_block.exited_at && new Date(d().exit_block.exited_at).toLocaleString('en-IN')} />
                    </div>
                  </div>
                </Show>

                <Show when={d().strategy_signal}>
                  <div class="space-y-2">
                    <h3 class="text-[10px] text-gray-500 font-black uppercase tracking-widest">Strategy & Guard Trail</h3>
                    <div class="grid grid-cols-2 gap-4 bg-white/[0.02] border border-white/5 rounded-xl p-4">
                      <Field label="Strategy" value={d().strategy_signal.strategy_slug} />
                      <Field label="Action" value={d().strategy_signal.action} />
                      <Field label="Outcome" value={d().strategy_signal.outcome} />
                      <Field label="Reason" value={d().strategy_signal.reason} />
                    </div>
                    <Show when={d().strategy_signal.guard_results?.length}>
                      <ul class="space-y-1">
                        <For each={d().strategy_signal.guard_results}>
                          {(g) => (
                            <li class="flex items-center justify-between text-xs bg-white/[0.02] border border-white/5 rounded-lg px-3 py-2">
                              <span class="text-gray-300">{g.guard?.split('::').pop()}</span>
                              <span class={`font-black uppercase text-[9px] px-2 py-0.5 rounded-full ${g.result === 'pass' ? 'bg-emerald-500/10 text-emerald-400' : 'bg-rose-500/10 text-rose-400'}`}>
                                {g.result}
                              </span>
                            </li>
                          )}
                        </For>
                      </ul>
                    </Show>
                  </div>
                </Show>

                <details class="bg-white/[0.02] border border-white/5 rounded-xl p-4">
                  <summary class="text-[10px] text-gray-500 font-black uppercase tracking-widest cursor-pointer">Raw Data</summary>
                  <pre class="text-[10px] text-gray-400 mt-3 overflow-x-auto">{JSON.stringify({ config_snapshot: d().config_snapshot, meta: d().meta }, null, 2)}</pre>
                </details>
              </div>
            )}
          </Show>
        </div>
      </div>
    </Show>
  )
}
```

- [ ] **Step 2: Manual verification**

Run: `cd dashboard && npm run dev`. Navigate to `/positions`, click a row. Confirm:
- Drawer slides in from the right, shows a loading state briefly, then the position's fields.
- Escape key, the backdrop click, and the × button all close the drawer.
- For a position with no linked `Strategies::Signal`, the "Strategy & Guard Trail" section does not render.
- For a closed position, the "Exit" section renders; for an open position it doesn't.
- The "Raw Data" `<details>` is collapsed by default and expands on click.

- [ ] **Step 3: Commit**

```bash
cd dashboard
git add src/components/positions/PositionDetailDrawer.jsx
git commit -m "feat: add PositionDetailDrawer for full position lifecycle detail"
```

---

### Task 6: Wire drawer into the list page (uncomment/finalize) and end-to-end verification

**Files:**
- Modify: `dashboard/src/views/Positions.jsx` (only if Task 4 Step 3 required temporarily disabling the drawer import/usage)

**Interfaces:**
- Consumes: `PositionDetailDrawer` from Task 5 (now that it exists), `selectedId`/`setSelectedId` already defined in Task 4.
- Produces: fully working `/positions` page — no further consumers.

- [ ] **Step 1: Restore the drawer wiring if it was disabled**

If Task 4 Step 3 required commenting out `<PositionDetailDrawer />` or the `onClick`/`selectedId` wiring because the component didn't exist yet, restore it now — the file already shown in Task 4 Step 1 has the drawer wired in from the start, so this step is a no-op unless you deviated from that code.

- [ ] **Step 2: Full end-to-end manual verification**

Run: `cd dashboard && npm run dev` (and ensure the Rails API is running on the port the dashboard proxies to, per `./bin/dev` in the main repo).

Walk through:
1. Navigate to `/positions` via the sidebar "Positions" link (Portfolio section) — confirm it no longer routes to the Dashboard.
2. Confirm Open tab shows live positions with LTP updating (open the Dashboard in another tab to confirm both reflect the same live WS-driven PnL).
3. Switch to Closed tab, confirm today's closed positions list (matches what `/api/positions` `closed` already returns — no new filter UI was added in this plan, only the base list + detail feature).
4. Click an open position row → drawer opens, shows entry context matching what's in the DB for that tracker (spot-check one field, e.g. `entry_tf`, against `PositionTracker.find(id).entry_tf` in `rails console`).
5. Click a closed position row → drawer opens, shows the Exit section.
6. If any position in the list was entered via the strategy platform (check `PositionTracker.where.not(alpha_source: nil)` in `rails console`, or use one of the `supertrend_v1`/`supertrend-adx`/`vwap-reversal` positions from prior sessions), open its drawer and confirm the Strategy & Guard Trail section renders with the guard list.
7. Close the drawer via all three methods (X, backdrop, Escape) and confirm each works.

- [ ] **Step 3: Commit (only if Step 1 required changes)**

```bash
cd dashboard
git add src/views/Positions.jsx
git commit -m "fix: restore PositionDetailDrawer wiring in Positions.jsx"
```

If Step 1 was a no-op, skip this commit — there is nothing to commit.
