# Automated Calibration System — UI Additions Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add (1) the on-demand AI snapshot endpoint + frontend button on the Analysis view, and (2) the `CalibrationRunsPanel` on the Settings view showing pending calibration runs with an Apply action.

**Architecture:** `Ai::AiSnapshotPromptBuilder` (pure service) → `Api::AnalysisController#ai_snapshot` (new action) → `useAnalysis.js` (new snapshot state + `fetchAiSnapshot`) → `AiInsights.vue` (new button + props) + `Analysis.vue` (prop wiring). Separately: `CalibrationRunsPanel.vue` (new component, fetches `/api/calibration_runs`) → `Settings.vue` (import + render).

**Tech Stack:** Rails 8, Ruby 3.3.4, Vue 3 + Vite (Composition API, `<script setup>`), raw `fetch` API (matching existing composable pattern), RSpec request specs, Vitest (if test infra available — skip frontend test steps if Vitest is not configured).

**Prerequisite:** Core pipeline plan (`2026-03-17-automated-calibration-core.md`) must be fully implemented first — `CalibrationRun` model and `GET /api/calibration_runs` endpoint must exist.

---

## Chunk 1: Backend — AI Snapshot Service + Endpoint

### Task 1: `Ai::AiSnapshotPromptBuilder`

**Files:**
- Create: `app/services/ai/ai_snapshot_prompt_builder.rb`
- Test: `spec/services/ai/ai_snapshot_prompt_builder_spec.rb`

**Background:** Pure function — no I/O, no external calls. Receives pre-resolved context params from the controller and assembles a compact prompt for Ollama. All params are optional; the prompt degrades gracefully when any is nil. Returns an array of `{ role:, content: }` message hashes for direct use with `Services::Ai::OpenaiClient.instance.chat(messages: [...])`. Uses `TradingSession::Service.market_closed?` internally for session context — this is a time-only check, no I/O, so it is permitted in a pure function.

- [ ] **Step 1: Write failing tests**

```ruby
# spec/services/ai/ai_snapshot_prompt_builder_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AiSnapshotPromptBuilder do
  let(:full_params) do
    {
      index_key:         'NIFTY',
      ltp:               22450.0,
      smc:               { 'trend' => 'bullish', 'structure' => 'BOS confirmed' },
      regime:            { 'label' => 'trending', 'strength' => 0.8 },
      calibration_stats: { 'avg_gain' => 14.2, 'avg_retrace_abs' => 3.1 }
    }
  end

  describe '.build' do
    subject(:messages) { described_class.build(**full_params) }

    it 'returns an array of message hashes' do
      expect(messages).to be_an(Array)
      expect(messages).not_to be_empty
    end

    it 'each message has :role and :content keys' do
      messages.each do |msg|
        expect(msg).to have_key(:role)
        expect(msg).to have_key(:content)
      end
    end

    it 'includes a system message' do
      roles = messages.map { |m| m[:role] }
      expect(roles).to include('system')
    end

    it 'includes a user message with index_key' do
      user_msg = messages.find { |m| m[:role] == 'user' }
      expect(user_msg).not_to be_nil
      expect(user_msg[:content]).to include('NIFTY')
    end

    it 'includes LTP in the user prompt' do
      user_msg = messages.find { |m| m[:role] == 'user' }
      expect(user_msg[:content]).to include('22450')
    end

    context 'with all params nil' do
      it 'still returns valid message array without raising' do
        messages = described_class.build(
          index_key: 'NIFTY', ltp: nil, smc: nil, regime: nil, calibration_stats: nil
        )
        expect(messages).to be_an(Array)
        expect(messages.size).to be >= 1
      end
    end

    context 'with only index_key provided' do
      it 'builds a minimal but valid prompt' do
        messages = described_class.build(
          index_key: 'SENSEX', ltp: nil, smc: nil, regime: nil, calibration_stats: nil
        )
        user_msg = messages.find { |m| m[:role] == 'user' }
        expect(user_msg[:content]).to include('SENSEX')
      end
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/services/ai/ai_snapshot_prompt_builder_spec.rb -f d
```

Expected: FAIL — `uninitialized constant Ai::AiSnapshotPromptBuilder`

- [ ] **Step 3: Write the service**

```ruby
# app/services/ai/ai_snapshot_prompt_builder.rb
# frozen_string_literal: true

module Ai
  # Assembles a compact Ollama prompt for on-demand AI market snapshots.
  #
  # Pure function — all context is passed in, no I/O.
  # All params are optional; the prompt degrades gracefully with nil inputs.
  #
  # Returns an Array of { role: String, content: String } hashes
  # for direct use with Services::Ai::OpenaiClient.instance.chat(messages: [...])
  class AiSnapshotPromptBuilder
    SYSTEM_PROMPT = <<~SYSTEM.strip
      You are a concise intraday options trading assistant for Indian index markets.
      Given current market context, provide a brief trading outlook in 3-5 bullet points.
      Focus on: trend direction, key risk levels, and whether conditions favour entry.
      Be direct, specific, and quantitative where possible. Avoid generic statements.
    SYSTEM

    # @param index_key [String] 'NIFTY', 'SENSEX', etc.
    # @param ltp [Float, nil] current last traded price
    # @param smc [Hash, nil] SMC analysis data (trend, structure, etc.)
    # @param regime [Hash, nil] market regime data (label, strength, etc.)
    # @param calibration_stats [Hash, nil] latest CalibrationRun raw_stats
    # @return [Array<Hash>] [{role: 'system', content: ...}, {role: 'user', content: ...}]
    def self.build(index_key:, ltp:, smc:, regime:, calibration_stats:)
      user_content = build_user_prompt(
        index_key: index_key.to_s.upcase,
        ltp: ltp,
        smc: smc,
        regime: regime,
        calibration_stats: calibration_stats
      )

      [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user',   content: user_content }
      ]
    end

    def self.build_user_prompt(index_key:, ltp:, smc:, regime:, calibration_stats:)
      session_context = TradingSession::Service.market_closed? ? 'After market hours' : 'Market open'

      lines = ["## #{index_key} Snapshot Request — #{Time.current.strftime('%Y-%m-%d %H:%M IST')}"]
      lines << "Session: #{session_context}"
      lines << "LTP: #{ltp || 'unavailable'}"
      lines << ''

      if smc.present?
        lines << '### Market Structure (SMC)'
        smc.each { |k, v| lines << "- #{k}: #{v}" }
        lines << ''
      end

      if regime.present?
        lines << '### Market Regime'
        regime.each { |k, v| lines << "- #{k}: #{v}" }
        lines << ''
      end

      if calibration_stats.present?
        lines << '### Historical Options Stats (last calibration)'
        lines << "- Avg gain: #{calibration_stats['avg_gain']}%"
        lines << "- Avg retrace: #{calibration_stats['avg_retrace_abs']}%"
        lines << "- Avg loss: #{calibration_stats['avg_loss_abs']}%" if calibration_stats['avg_loss_abs']
        lines << ''
      end

      lines << 'Provide a brief trading outlook based on the above context.'
      lines.join("\n")
    end

    private_class_method :build_user_prompt
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/ai/ai_snapshot_prompt_builder_spec.rb -f d
```

Expected: All examples pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/ai/ai_snapshot_prompt_builder.rb \
        spec/services/ai/ai_snapshot_prompt_builder_spec.rb
git commit -m "feat: add Ai::AiSnapshotPromptBuilder for on-demand AI snapshots"
```

---

### Task 2: `AnalysisController#ai_snapshot` + route + request spec

**Files:**
- Modify: `app/controllers/api/analysis_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/api/analysis_ai_snapshot_spec.rb`

**Background:** New `ai_snapshot` action added to the existing `AnalysisController`. Route is a standalone `post` entry (analysis routes are individual routes, not a `resource` block). The controller resolves the instrument and LTP exactly like `show` does, then delegates to `Ai::AiSnapshotPromptBuilder.build` and `Services::Ai::OpenaiClient.instance.chat`. Does NOT write to `AnalysisStore` — the snapshot is transient. Returns `{ snapshot: "<string>", generated_at: "<ISO8601>" }` on success, 503 on AI errors.

**Note:** `Ai::AiSnapshotPromptBuilder.build` returns a two-element array `[{role: 'system', ...}, {role: 'user', ...}]` — the builder owns the full message array including the system prompt. This is a deliberate deviation from the spec's original interface (which showed a user-only array); the builder encapsulation is cleaner and consistent with how `Services::Ai::OpenaiClient` expects messages.

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/api/analysis_ai_snapshot_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/analysis/:index_key/ai_snapshot', type: :request do
  let(:instrument) { create(:instrument, :nifty_future) }

  before do
    # Stub IndexConfigLoader to return NIFTY
    allow(IndexConfigLoader).to receive(:load_indices).and_return([
      { key: 'NIFTY', segment: instrument.exchange_segment, sid: instrument.security_id.to_s }
    ])
    allow(Instrument).to receive(:find_by_sid_and_segment).and_return(instrument)
    allow(Live::TickCache).to receive(:ltp).and_return(22450.0)
    allow(AnalysisStore).to receive(:read_all).and_return({
      smc: { data: { 'trend' => 'bullish' } },
      regime: { data: { 'label' => 'trending' } }
    })
    allow(CalibrationRun).to receive_message_chain(:where, :order, :first).and_return(nil)
  end

  context 'when OpenaiClient returns a response' do
    before do
      client = instance_double(Services::Ai::OpenaiClient, enabled?: true, chat: 'Bullish outlook. Key level 22000.')
      allow(Services::Ai::OpenaiClient).to receive(:instance).and_return(client)
    end

    it 'returns 200 with snapshot and generated_at' do
      post '/api/analysis/NIFTY/ai_snapshot'
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to have_key('snapshot')
      expect(json).to have_key('generated_at')
    end

    it 'returns the AI response as snapshot' do
      post '/api/analysis/NIFTY/ai_snapshot'
      json = JSON.parse(response.body)
      expect(json['snapshot']).to include('Bullish outlook')
    end
  end

  context 'when OpenaiClient raises Net::ReadTimeout' do
    before do
      client = instance_double(Services::Ai::OpenaiClient, enabled?: true)
      allow(client).to receive(:chat).and_raise(Net::ReadTimeout)
      allow(Services::Ai::OpenaiClient).to receive(:instance).and_return(client)
    end

    it 'returns 503' do
      post '/api/analysis/NIFTY/ai_snapshot'
      expect(response).to have_http_status(:service_unavailable)
    end

    it 'returns a human-readable error' do
      post '/api/analysis/NIFTY/ai_snapshot'
      json = JSON.parse(response.body)
      expect(json['error']).to include('timed out')
    end
  end

  context 'when OpenaiClient raises a generic error' do
    before do
      client = instance_double(Services::Ai::OpenaiClient, enabled?: true)
      allow(client).to receive(:chat).and_raise(StandardError, 'connection refused')
      allow(Services::Ai::OpenaiClient).to receive(:instance).and_return(client)
    end

    it 'returns 503' do
      post '/api/analysis/NIFTY/ai_snapshot'
      expect(response).to have_http_status(:service_unavailable)
    end
  end

  context 'when AI client is not enabled' do
    before do
      client = instance_double(Services::Ai::OpenaiClient, enabled?: false)
      allow(Services::Ai::OpenaiClient).to receive(:instance).and_return(client)
    end

    it 'returns 503 without calling chat' do
      post '/api/analysis/NIFTY/ai_snapshot'
      expect(response).to have_http_status(:service_unavailable)
      json = JSON.parse(response.body)
      expect(json['error']).to include('not configured')
    end
  end

  context 'with an unknown index_key' do
    before do
      allow(IndexConfigLoader).to receive(:load_indices).and_return([])
      allow(Instrument).to receive(:find_by_sid_and_segment).and_return(nil)
    end

    it 'returns 404' do
      post '/api/analysis/UNKNOWN/ai_snapshot'
      expect(response).to have_http_status(:not_found)
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/requests/api/analysis_ai_snapshot_spec.rb -f d
```

Expected: FAIL — routing error (route not defined yet).

- [ ] **Step 3: Add route**

In `config/routes.rb`, inside the `namespace :api` block, after the existing `analysis` routes:

```ruby
post 'analysis/:index_key/ai_snapshot', to: 'analysis#ai_snapshot', as: :analysis_ai_snapshot
```

Note: `to: 'analysis#ai_snapshot'` (no `api/` prefix) because this is already inside `namespace :api`.

- [ ] **Step 4: Add `ai_snapshot` action to `AnalysisController`**

In `app/controllers/api/analysis_controller.rb`, add after the `historical` action and before `private`:

```ruby
# POST /api/analysis/:index_key/ai_snapshot
# On-demand AI analysis using current market context. Synchronous — may take up to 120s.
# Does NOT write to AnalysisStore — snapshot is transient and display-only.
def ai_snapshot
  index_key  = params[:index_key].to_s.upcase
  instrument = find_instrument(index_key)
  return render json: { error: 'Index not found' }, status: :not_found unless instrument

  ltp   = Live::TickCache.ltp(instrument.exchange_segment, instrument.security_id)
  stored = AnalysisStore.read_all(index_key)

  latest_run = CalibrationRun.where(symbol: index_key).order(created_at: :desc).first

  client = Services::Ai::OpenaiClient.instance
  unless client.enabled?
    return render json: { error: 'AI service not configured' }, status: :service_unavailable
  end

  messages = Ai::AiSnapshotPromptBuilder.build(
    index_key:         index_key,
    ltp:               ltp&.to_f,
    smc:               stored[:smc]&.dig(:data),
    regime:            stored[:regime]&.dig(:data),
    calibration_stats: latest_run&.raw_stats
  )

  ai_response = client.chat(messages: messages, temperature: 0.3)

  render json: { snapshot: ai_response, generated_at: Time.current.iso8601 }
rescue Net::ReadTimeout, Faraday::TimeoutError => e
  Rails.logger.warn("[AnalysisController] ai_snapshot timeout: #{e.class}")
  render json: { error: 'AI service unavailable — timed out' }, status: :service_unavailable
rescue StandardError => e
  Rails.logger.error("[AnalysisController] ai_snapshot error: #{e.class} - #{e.message}")
  render json: { error: 'AI service unavailable' }, status: :service_unavailable
end
```

- [ ] **Step 5: Run request specs**

```bash
bundle exec rspec spec/requests/api/analysis_ai_snapshot_spec.rb -f d
```

Expected: All examples pass.

- [ ] **Step 6: Run RuboCop**

```bash
bundle exec rubocop app/controllers/api/analysis_controller.rb config/routes.rb
```

Expected: No offenses.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/analysis_controller.rb \
        config/routes.rb \
        spec/requests/api/analysis_ai_snapshot_spec.rb
git commit -m "feat: add AnalysisController#ai_snapshot endpoint"
```

---

## Chunk 2: Frontend — Composable + AI Snapshot UI

### Task 3: `useAnalysis.js` — add snapshot state

**Files:**
- Modify: `dashboard/src/composables/useAnalysis.js`

**Background:** Three new reactive refs (`snapshotLoading`, `snapshotData`, `snapshotError`) and a new `fetchAiSnapshot` function. `snapshotData` is reset to `null` only in `switchIndex()` — NOT in `fetchLive()`. This ensures background polls don't clear a visible snapshot. Uses raw `fetch` (matching existing pattern in this file, not Axios).

- [ ] **Step 1: Read the current file**

Read `dashboard/src/composables/useAnalysis.js` to understand the current return shape before editing.

- [ ] **Step 2: Add snapshot state and function**

Add the following to `useAnalysis.js`:

```js
// --- NEW: snapshot state ---
const snapshotLoading = ref(false)
const snapshotData    = ref(null)
const snapshotError   = ref(null)

async function fetchAiSnapshot() {
  snapshotLoading.value = true
  snapshotError.value   = null
  try {
    const res = await fetch(`/api/analysis/${currentIndex.value}/ai_snapshot`, { method: 'POST' })
    if (!res.ok) {
      const data = await res.json().catch(() => ({}))
      throw new Error(data.error || `HTTP ${res.status}`)
    }
    const data = await res.json()
    snapshotData.value = data.snapshot
  } catch (e) {
    snapshotError.value = e.message || 'Snapshot failed'
  } finally {
    snapshotLoading.value = false
  }
}
```

In `switchIndex()`, reset `snapshotData` to null:
```js
function switchIndex(key) {
  currentIndex.value = key
  liveData.value = null
  historicalData.value = null
  snapshotData.value = null   // ← add this line
  snapshotError.value = null  // ← add this line
  fetchLive(key)
}
```

Add to the return object:
```js
snapshotLoading,
snapshotData,
snapshotError,
fetchAiSnapshot,
```

- [ ] **Step 3: Verify the file compiles**

```bash
cd dashboard && npx vite build --mode development 2>&1 | tail -5
```

Expected: No syntax errors.

- [ ] **Step 4: Commit**

```bash
git add dashboard/src/composables/useAnalysis.js
git commit -m "feat: add snapshot state and fetchAiSnapshot to useAnalysis composable"
```

---

### Task 4: `AiInsights.vue` — add Snapshot button and new props

**Files:**
- Modify: `dashboard/src/components/analysis/AiInsights.vue`

**Background:** Accepts four new props: `snapshotData` (string/null), `snapshotLoading` (bool), `snapshotError` (string/null), `onSnapshot` (function). When `snapshotData` is non-null, it is displayed instead of the polled `analysis` prop. A "🤖 Snapshot" button triggers `onSnapshot`. Shows spinner overlay during load, inline error on failure. Snapshot display persists until the user switches symbol (controlled by the composable, not this component).

- [ ] **Step 1: Read the current file**

Read `dashboard/src/components/analysis/AiInsights.vue` to understand the existing template before editing.

- [ ] **Step 2: Update the component**

Replace the component with:

```vue
<script setup>
import { computed } from 'vue'

const props = defineProps({
  analysis:        [String, Object, null],
  snapshotData:    { default: null },      // String | null — omit type to avoid Vue null-type warning
  snapshotLoading: { type: Boolean, default: false },
  snapshotError:   { default: null },      // String | null — omit type to avoid Vue null-type warning
  onSnapshot:      { type: Function, default: null }
})

// Snapshot takes display priority over polled analysis
const displayText = computed(() => props.snapshotData ?? (
  typeof props.analysis === 'string' ? props.analysis :
  props.analysis ? JSON.stringify(props.analysis, null, 2) : null
))

const isLiveSnapshot = computed(() => props.snapshotData !== null)

function formatMarkdown(raw) {
  if (!raw) return ''
  return raw
    .replace(/\*\*(.*?)\*\*/g, '<strong class="text-white">$1</strong>')
    .replace(/#{1,3}\s(.*?)(\n|$)/g, '<div class="text-cyan-400 font-black text-xs tracking-wider mt-3 mb-1">$1</div>')
    .replace(/\n/g, '<br>')
}
</script>

<template>
  <div class="glass rounded-2xl p-6 glass-hover">
    <div class="flex items-center justify-between gap-3 mb-5">
      <div class="flex items-center gap-3">
        <span class="text-[10px] font-black text-gray-500 tracking-[0.2em] uppercase">🤖 AI Analysis</span>
        <span v-if="isLiveSnapshot"
          class="text-[9px] font-bold text-emerald-400 bg-emerald-400/10 px-2 py-0.5 rounded uppercase tracking-wider">
          🔴 Live snapshot
        </span>
        <span v-else-if="displayText" class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span>
      </div>

      <button
        v-if="onSnapshot"
        @click="onSnapshot()"
        :disabled="snapshotLoading"
        class="px-3 py-1.5 rounded-lg text-[9px] font-black uppercase tracking-widest glass border border-white/10 text-gray-400 hover:text-cyan-300 hover:border-cyan-500/30 transition-all duration-300 disabled:opacity-40 flex items-center gap-1.5"
      >
        <span v-if="snapshotLoading" class="w-3 h-3 border border-gray-400 border-t-transparent rounded-full animate-spin"></span>
        <span>{{ snapshotLoading ? 'Fetching...' : '🤖 Snapshot' }}</span>
      </button>
    </div>

    <!-- Inline error -->
    <div v-if="snapshotError" class="text-rose-400 text-[10px] font-bold mb-3 px-2 py-1 bg-rose-500/10 rounded">
      ⚠ {{ snapshotError }}
    </div>

    <!-- Analysis content (with loading overlay) -->
    <div class="relative">
      <div v-if="displayText"
        class="text-xs leading-relaxed text-gray-400 max-h-[500px] overflow-y-auto pr-2 scrollbar-thin"
        :class="{ 'opacity-30': snapshotLoading }"
        v-html="formatMarkdown(displayText)">
      </div>

      <div v-else-if="!snapshotLoading" class="text-center py-10">
        <div class="text-gray-600 text-[10px] font-bold tracking-widest uppercase">
          AI insights unavailable
        </div>
        <div class="text-gray-700 text-[9px] mt-2 tracking-wider">
          The AI model is either processing data or timed out. Please wait or check model performance.
        </div>
      </div>

      <!-- Loading overlay (when snapshotLoading and no existing content) -->
      <div v-if="snapshotLoading && !displayText" class="flex items-center justify-center py-10">
        <div class="w-5 h-5 border border-white/10 border-t-cyan-400 rounded-full animate-spin mr-3"></div>
        <span class="text-[10px] text-gray-500 font-bold tracking-widest uppercase">Generating snapshot...</span>
      </div>
    </div>
  </div>
</template>
```

- [ ] **Step 3: Verify build**

```bash
cd dashboard && npx vite build --mode development 2>&1 | tail -5
```

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add dashboard/src/components/analysis/AiInsights.vue
git commit -m "feat: add Snapshot button and snapshot display to AiInsights.vue"
```

---

### Task 5: `Analysis.vue` — wire new props

**Files:**
- Modify: `dashboard/src/views/Analysis.vue`

**Background:** Destructure four new returns from `useAnalysis`: `snapshotLoading`, `snapshotData`, `snapshotError`, `fetchAiSnapshot`. Bind them as props on the `<AiInsights>` component. No other changes.

- [ ] **Step 1: Read the current file**

Read `dashboard/src/views/Analysis.vue` to locate the `useAnalysis` destructure and `<AiInsights>` usage before editing.

- [ ] **Step 2: Update the `useAnalysis` destructure**

In the `<script setup>` block, expand the `useAnalysis()` destructure to include:
```js
const {
  currentIndex, liveData, historicalData,
  loading, historicalLoading, error,
  fetchLive, fetchHistorical, switchIndex,
  snapshotLoading, snapshotData, snapshotError, fetchAiSnapshot  // ← add these
} = useAnalysis()
```

- [ ] **Step 3: Update `<AiInsights>` binding**

Find the `<AiInsights>` usage in the template and add the four new props:
```vue
<AiInsights
  :analysis="enrichedData?.ai_analysis"
  :snapshotData="snapshotData"
  :snapshotLoading="snapshotLoading"
  :snapshotError="snapshotError"
  :onSnapshot="fetchAiSnapshot"
/>
```

Note: the existing `:analysis` prop name may differ — check the current template and use the exact prop name that maps to the AI analysis text.

- [ ] **Step 4: Verify build**

```bash
cd dashboard && npx vite build --mode development 2>&1 | tail -5
```

Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add dashboard/src/views/Analysis.vue
git commit -m "feat: wire AI snapshot props in Analysis.vue"
```

---

## Chunk 3: Frontend — Calibration Runs Panel

### Task 6: `CalibrationRunsPanel.vue` — new component

**Files:**
- Create: `dashboard/src/components/settings/CalibrationRunsPanel.vue`

**Background:** Displays the last 5 `CalibrationRun` records for a given symbol. Fetches from `GET /api/calibration_runs?limit=5` (returns all symbols — filter client-side by `symbol` prop). Shows proposed config diff (proposed vs `current_snapshot`). "Apply" button POSTs to `/api/calibration_runs/:id/apply`. Applied runs show applied date. Regime shift runs show amber warning badge. A 10% threshold is already applied server-side (`proposed_patch` only contains keys with ≥10% change) — display all keys in `proposed_patch` without further filtering.

- [ ] **Step 1: Write the component**

```vue
<!-- dashboard/src/components/settings/CalibrationRunsPanel.vue -->
<script setup>
import { ref, computed, onMounted } from 'vue'

const props = defineProps({
  symbol: { type: String, required: true }
})

const runs        = ref([])
const loading     = ref(false)
const error       = ref(null)
const applying    = ref(null)   // run ID currently being applied
const applyError  = ref(null)
const applySuccess = ref(false)  // shows "✅ Config updated" toast after apply

async function fetchRuns() {
  loading.value = true
  error.value   = null
  try {
    const res = await fetch('/api/calibration_runs?limit=20')
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    const all = await res.json()
    runs.value = all.filter(r => r.symbol === props.symbol).slice(0, 5)
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

async function applyRun(run) {
  if (applying.value) return
  // Guard: ask for confirmation before writing live config
  if (!window.confirm(`Apply calibration patch for ${props.symbol}? This will update live config.`)) return
  applying.value   = run.id
  applyError.value = null
  applySuccess.value = false
  try {
    const res = await fetch(`/api/calibration_runs/${run.id}/apply`, { method: 'POST' })
    const data = await res.json()
    if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`)
    applySuccess.value = true
    setTimeout(() => { applySuccess.value = false }, 5000)
    // Refresh list to show updated applied_at
    await fetchRuns()
  } catch (e) {
    applyError.value = e.message
  } finally {
    applying.value = null
  }
}

// Build a flat diff list: [{key, current, proposed}]
function buildDiff(proposed_patch, current_snapshot) {
  const pairs = []
  function walk(obj, prefix) {
    for (const [k, v] of Object.entries(obj || {})) {
      const fullKey = prefix ? `${prefix}.${k}` : k
      if (v !== null && typeof v === 'object') {
        walk(v, fullKey)
      } else {
        const cur = current_snapshot?.[fullKey]
        pairs.push({ key: fullKey, current: cur ?? null, proposed: v })
      }
    }
  }
  walk(proposed_patch, '')
  return pairs
}

const pendingRuns = computed(() => runs.value.filter(r => !r.applied_at))

onMounted(fetchRuns)
</script>

<template>
  <div class="mt-8 border-t border-gray-800 pt-6">
    <div class="flex items-center justify-between mb-4">
      <h3 class="text-sm font-bold text-gray-300 uppercase tracking-widest">
        📊 Calibration Runs — {{ symbol }}
      </h3>
      <button
        @click="fetchRuns"
        :disabled="loading"
        class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider disabled:opacity-40"
      >
        {{ loading ? '↻ Loading...' : '↻ Refresh' }}
      </button>
    </div>

    <div v-if="error" class="text-rose-400 text-xs mb-4">⚠ {{ error }}</div>
    <div v-if="applyError" class="text-rose-400 text-xs mb-4">Apply failed: {{ applyError }}</div>
    <div v-if="applySuccess" class="text-emerald-400 text-xs mb-4 font-bold">
      ✅ Config updated — daemon picks up in ~30s
    </div>

    <div v-if="loading && !runs.length" class="text-gray-600 text-xs py-4">Loading...</div>

    <div v-else-if="!runs.length" class="text-gray-700 text-xs py-4">
      No calibration runs yet. Runs appear after the weekly job executes.
    </div>

    <div v-else class="space-y-3">
      <div
        v-for="run in runs"
        :key="run.id"
        class="bg-gray-900 border rounded-lg p-4 relative"
        :class="run.is_regime_shift ? 'border-amber-600/40' : 'border-gray-800'"
      >
        <!-- Regime shift badge -->
        <div v-if="run.is_regime_shift"
          class="absolute top-2 right-2 text-[9px] font-black text-amber-400 bg-amber-400/10 px-2 py-0.5 rounded uppercase tracking-wider">
          ⚠ Regime shift
        </div>

        <!-- Run header -->
        <div class="flex items-center gap-4 mb-3">
          <span class="text-[10px] font-bold text-gray-400">
            {{ new Date(run.created_at).toLocaleDateString('en-IN') }}
          </span>
          <span class="text-[10px] text-gray-600">{{ run.weeks_analyzed }}w · {{ run.strike_mode }}</span>
          <span v-if="run.applied_at" class="text-[9px] text-emerald-400 font-bold">
            ✓ Applied {{ new Date(run.applied_at).toLocaleDateString('en-IN') }}
            <span v-if="run.applied_by"> via {{ run.applied_by }}</span>
          </span>
        </div>

        <!-- Config diff table -->
        <div class="mb-3">
          <template v-for="diff in buildDiff(run.proposed_patch, run.current_snapshot)" :key="diff.key">
            <div class="flex items-center gap-2 text-[10px] font-mono py-0.5">
              <span class="text-gray-600 flex-1 truncate">{{ diff.key }}</span>
              <span class="text-gray-500">{{ diff.current !== null ? diff.current : '—' }}</span>
              <span class="text-gray-600 mx-1">→</span>
              <span class="text-cyan-400 font-bold">{{ diff.proposed }}</span>
            </div>
          </template>
          <div v-if="buildDiff(run.proposed_patch, run.current_snapshot).length === 0"
            class="text-gray-600 text-[9px] italic">
            No significant config changes (&lt;10% deviation from current)
          </div>
        </div>

        <!-- Apply button (only for pending runs) -->
        <button
          v-if="!run.applied_at"
          @click="applyRun(run)"
          :disabled="applying === run.id"
          class="px-4 py-1.5 text-[10px] font-black uppercase tracking-widest rounded border transition-all"
          :class="applying === run.id
            ? 'border-gray-700 text-gray-600 cursor-not-allowed'
            : 'border-cyan-700 text-cyan-400 hover:bg-cyan-900/20 hover:border-cyan-500'"
        >
          {{ applying === run.id ? 'Applying...' : 'Apply' }}
        </button>
      </div>
    </div>
  </div>
</template>
```

- [ ] **Step 2: Verify build**

```bash
cd dashboard && npx vite build --mode development 2>&1 | tail -5
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add dashboard/src/components/settings/CalibrationRunsPanel.vue
git commit -m "feat: add CalibrationRunsPanel.vue for Settings view"
```

---

### Task 7: `Settings.vue` — render `CalibrationRunsPanel`

**Files:**
- Modify: `dashboard/src/views/Settings.vue`

**Background:** Import `CalibrationRunsPanel` and render it below the existing config tree editor, once for each tracked symbol (`['NIFTY', 'SENSEX']`). No changes to the existing editor logic.

- [ ] **Step 1: Read the current file**

Read `dashboard/src/views/Settings.vue` to locate the import block and the bottom of the template before editing.

- [ ] **Step 2: Add the import**

In the `<script setup>` block (or `<script>` if using Options API), add:
```js
import CalibrationRunsPanel from '../components/settings/CalibrationRunsPanel.vue'
```

- [ ] **Step 3: Add the panel below the config editor**

At the bottom of the `<template>` content (after the config tree editor `</div>`), add:
```vue
<!-- Calibration Runs Panels -->
<div class="mt-12 max-w-7xl mx-auto w-full space-y-6">
  <CalibrationRunsPanel
    v-for="sym in ['NIFTY', 'SENSEX']"
    :key="sym"
    :symbol="sym"
  />
</div>
```

- [ ] **Step 4: Verify build**

```bash
cd dashboard && npx vite build --mode development 2>&1 | tail -5
```

Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add dashboard/src/views/Settings.vue
git commit -m "feat: add CalibrationRunsPanel to Settings.vue"
```

---

## Chunk 4: Full Run Verification

### Task 8: End-to-end verification

- [ ] **Step 1: Run all new/modified specs**

```bash
bundle exec rspec \
  spec/services/ai/ai_snapshot_prompt_builder_spec.rb \
  spec/requests/api/analysis_ai_snapshot_spec.rb \
  -f d
```

Expected: All pass, 0 failures.

- [ ] **Step 2: Run RuboCop on all modified backend files (including specs)**

```bash
bundle exec rubocop \
  app/services/ai/ai_snapshot_prompt_builder.rb \
  app/controllers/api/analysis_controller.rb \
  config/routes.rb \
  spec/services/ai/ai_snapshot_prompt_builder_spec.rb \
  spec/requests/api/analysis_ai_snapshot_spec.rb
```

Expected: No offenses (resolve any auto-correctable issues with `rubocop -A`).

- [ ] **Step 3: Verify frontend build is clean**

```bash
cd dashboard && npx vite build --mode development 2>&1; echo "Exit: $?"
```

Expected: Build completes with `Exit: 0`. Any errors will appear in the output above.

- [ ] **Step 4: Smoke test route and prompt builder via `rails runner`**

```bash
bundle exec rails runner '
puts Rails.application.routes.url_helpers.api_analysis_ai_snapshot_path("NIFTY")
msgs = Ai::AiSnapshotPromptBuilder.build(index_key: "NIFTY", ltp: 22000.0, smc: nil, regime: nil, calibration_stats: nil)
puts msgs.map { |m| "#{m[:role]}: #{m[:content][0..50]}..." }
'
```

Expected output:
```
/api/analysis/NIFTY/ai_snapshot
system: You are a concise intraday options trading assistant...
user: ## NIFTY Snapshot Request — ...
```

- [ ] **Step 5: Commit any adjustments made during smoke test**

Only if changes were made during the smoke test steps above:

```bash
git add app/services/ai/ai_snapshot_prompt_builder.rb \
        app/controllers/api/analysis_controller.rb \
        config/routes.rb \
        spec/services/ai/ai_snapshot_prompt_builder_spec.rb \
        spec/requests/api/analysis_ai_snapshot_spec.rb
git commit -m "fix: address any UI smoke test issues"
```
