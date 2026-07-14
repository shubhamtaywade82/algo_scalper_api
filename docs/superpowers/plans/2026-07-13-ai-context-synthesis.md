# AI Context Synthesis — Research Kernel Narration Layer Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a narration layer on top of the already-built `Research::ExpectancyReport` (context → expectancy buckets) that produces grounded natural-language commentary — e.g. *"Historically, this context resembles 143 prior sessions. In 81% of them, ATM and ATM+1 calls produced the best risk-adjusted returns, while range-bound sessions with similar volatility underperformed."* The LLM **narrates already-computed facts**; it never invents a number, a bucket, or a probability that isn't already sitting in the `ExpectancyReport` output. This is the missing piece from the original research-goals conversation: "AI should not invent the context... AI then synthesizes those facts."

**Why now, not sooner:** everything upstream of this (`Research::ContextClassifier`, `Research::ExpectancyReport`, the Premium Lifecycle Board) had to exist first — there was nothing to narrate over until buckets with real sample sizes existed.

**Architecture:**

```
Research::ExpectancyReport.call (existing)
        │  buckets: [{context:, sample_size:, avg_return_pct:, win_rate_pct:, ...}, ...]
        ▼
Research::ContextSynthesizer            # pure: assembles a compact "facts payload"
        │  (optionally highlights one target_context against the rest)
        ▼
Research::SynthesisPromptBuilder        # pure: facts payload -> system+user prompt strings
        ▼
Research::ContextSynthesizerService     # orchestrator: prompt -> Services::Ai::OllamaClient.instance.chat
        │  (Timeout.timeout + sanity-check + deterministic fallback — same pattern as
        │   lib/services/ai/technical_analysis_agent/agent_runner.rb already uses)
        ▼
Research::ContextSynthesis (AR model)   # persists facts_payload + narrative + model_used + status
        ▼
Api::Research::ContextSynthesesController  # POST synthesize, GET show/index
        ▼
dashboard: "Synthesize" button on the Context → Expectancy panel
```

**Reuse — do not reinvent:**
- `Services::Ai::OllamaClient.instance.chat(messages:, model:, temperature:, log_context:)` (`lib/services/ai/ollama_client.rb`) — the singleton wrapper over the `ollama-client` gem (`Gemfile: gem 'ollama-client', '~> 1.1'`). No tool-calling needed here (synthesis is over precomputed facts, not live data-fetching), so skip `lib/services/ai/technical_analysis_agent/tool_registry.rb` entirely — mirror the simpler "facts prompt straight to `chat`" path.
- The **facts-prompt / synthesis-system-prompt pattern** in `lib/services/ai/technical_analysis_agent/agent_runner.rb` (`build_facts_prompt`, `build_synthesis_system_prompt`) — same idea: serialize only already-computed numbers into the user message, instruct the system prompt not to invent anything outside them.
- The **timeout + fallback pattern** already proven in `AiTechnicalAnalysisJob`/`agent_runner.rb`: `Timeout.timeout(ENV.fetch('AI_CONTEXT_SYNTHESIS_TIMEOUT', '20').to_i)` around the chat call, a `invalid_llm_output?`-style sanity check (blank / runaway-repetition guard), and a **deterministic fallback narrative** (plain string interpolation of the top/bottom bucket stats) if the LLM times out, errors, or fails the sanity check — the UI must never show nothing.
- ENV/config already wired: `OLLAMA_MODEL`, `OLLAMA_LOCAL_URL`/`OLLAMA_CLOUD_URL`, `OLLAMA_TIMEOUT`, `AlgoConfig.fetch.dig(:ai, :ollama_use_cloud/:enabled)` — no new AI-provider plumbing needed.

**Why synchronous, not a background job:** every other Research endpoint (`Pipeline.run`, `LifecycleRunner.run`) is already synchronous-with-real-API-calls in this module, and synthesis text isn't safety-critical (nothing trades off it directly) — a 20s worst-case timeout with an immediate deterministic fallback is simpler than adding polling UI + Solid Queue job + status endpoint for a manual "click to synthesize" action. If this proves too slow in practice once real usage shows up, escalate to a `Research::ContextSynthesisJob` + status-polling exactly like `AnalysisController`'s cache-first/background-refresh pattern — but don't build that speculatively now.

**Tech Stack:** Rails 8, `Services::Ai::OllamaClient` (existing), PostgreSQL (jsonb for facts_payload), RSpec (mock the client — no live Ollama calls in specs), SolidJS dashboard.

---

## Chunk 1: Facts Assembly (pure, no LLM, no DB)

### Task 1: `Research::ContextSynthesizer` — buckets → compact facts payload

**Files:**
- Create: `app/services/research/context_synthesizer.rb`
- Test: `spec/services/research/context_synthesizer_spec.rb`

**Background:** Takes the output of `Research::ExpectancyReport.call` (already-ranked buckets) plus an optional `target_context` (a `{dimension => label}` hash — either the caller's live "what's happening right now" snapshot via `Research::ContextClassifier.classify` + a subset of its keys, or a manually chosen bucket to explain). Produces a small, LLM-ready hash: total sample size, the target bucket's own stats (if it matches one), the best and worst buckets by avg return, and a plain list of all buckets sorted best-to-worst (capped, e.g. top 10) so the prompt stays short regardless of how many buckets exist.

- [ ] **Step 1: Write the synthesizer**

```ruby
# frozen_string_literal: true

module Research
  # Turns Research::ExpectancyReport's ranked buckets into a compact,
  # LLM-ready "facts payload" — the ONLY numbers the synthesis prompt is
  # allowed to reference. If target_context is given, the matching bucket
  # (if any) is called out separately so the narrative can say "this
  # specific context has historically done X" rather than a generic summary.
  class ContextSynthesizer
    MAX_BUCKETS_IN_PROMPT = 10

    class << self
      def build(buckets:, target_context: nil)
        ranked = buckets.first(MAX_BUCKETS_IN_PROMPT)

        {
          "total_buckets" => buckets.size,
          "total_sessions_analyzed" => buckets.sum { |b| b[:sample_size] },
          "target_context" => target_context,
          "target_bucket" => target_context && find_matching_bucket(buckets, target_context),
          "best_bucket" => buckets.max_by { |b| b[:avg_return_pct] || -Float::INFINITY },
          "worst_bucket" => buckets.min_by { |b| b[:avg_return_pct] || Float::INFINITY },
          "buckets" => ranked
        }
      end

      private

      def find_matching_bucket(buckets, target_context)
        buckets.find { |b| b[:context] == target_context }
      end
    end
  end
end
```

- [ ] **Step 2: Spec it** — cover: empty buckets, a target_context that matches a bucket exactly, a target_context that matches nothing (still returns best/worst), and the `MAX_BUCKETS_IN_PROMPT` cap.

### Task 2: `Research::SynthesisPromptBuilder` — facts payload → prompt strings

**Files:**
- Create: `app/services/research/synthesis_prompt_builder.rb`
- Test: `spec/services/research/synthesis_prompt_builder_spec.rb`

**Background:** Mirrors `agent_runner.rb#build_facts_prompt` / `#build_synthesis_system_prompt` — a system prompt that hard-constrains the model to the given numbers, and a user prompt that dumps the facts payload as readable text (not raw JSON — the model reads prose better than a JSON blob, per the existing agent's own convention).

- [ ] **Step 1: Write the prompt builder**

```ruby
# frozen_string_literal: true

module Research
  class SynthesisPromptBuilder
    class << self
      def system_prompt
        <<~PROMPT
          You are a research analyst summarizing ALREADY-COMPUTED historical
          option-premium statistics for a trading research platform. You do
          not have access to live market data and must not invent, estimate,
          or extrapolate any number that is not explicitly given to you below.
          Every percentage, count, or time value you mention must come
          directly from the facts provided. If the sample size for a bucket
          is small (fewer than ~10 sessions), say so explicitly and caveat
          the conclusion — do not present it as a strong pattern.
          Write 2-4 sentences. Be concrete: name the context labels and the
          numbers. Do not give trading advice or tell the user to buy/sell.
        PROMPT
      end

      def user_prompt(facts_payload)
        lines = ["Total historical sessions analyzed: #{facts_payload['total_sessions_analyzed']} " \
                 "across #{facts_payload['total_buckets']} distinct context buckets.", ""]

        if facts_payload["target_context"]
          lines << "Current/target context: #{format_context(facts_payload['target_context'])}"
          lines << (facts_payload["target_bucket"] ? format_bucket(facts_payload["target_bucket"]) \
                                                     : "No prior historical bucket exactly matches this context.")
          lines << ""
        end

        lines << "Best-performing historical context:"
        lines << format_bucket(facts_payload["best_bucket"])
        lines << ""
        lines << "Worst-performing historical context:"
        lines << format_bucket(facts_payload["worst_bucket"])
        lines << ""
        lines << "All buckets (ranked best to worst by avg return):"
        facts_payload["buckets"].each { |b| lines << "- #{format_bucket(b)}" }

        lines.join("\n")
      end

      private

      def format_context(context)
        context.map { |k, v| "#{k}=#{v}" }.join(", ")
      end

      def format_bucket(bucket)
        return "none" if bucket.nil?

        "#{format_context(bucket[:context] || bucket['context'])} — " \
          "#{bucket[:sample_size] || bucket['sample_size']} sessions, " \
          "avg peak return #{bucket[:avg_return_pct] || bucket['avg_return_pct']}%, " \
          "win rate #{bucket[:win_rate_pct] || bucket['win_rate_pct']}%, " \
          "avg time to peak #{bucket[:avg_time_to_peak_minutes] || bucket['avg_time_to_peak_minutes']} min, " \
          "avg drawdown #{bucket[:avg_drawdown_pct] || bucket['avg_drawdown_pct']}%"
      end
    end
  end
end
```

- [ ] **Step 2: Spec it** — assert the user prompt contains every number from the facts payload verbatim (a cheap "did we actually ground this" regression test), and that it degrades gracefully with no `target_context`.

---

## Chunk 2: Persistence

### Task 3: `research_context_syntheses` table + `Research::ContextSynthesis` model

**Files:**
- Create: `db/migrate/20260713150000_create_research_context_syntheses.rb`
- Create: `app/models/research/context_synthesis.rb`
- Update: `db/schema.rb` (hand-edit, same as the rest of this module — bundler is broken in the current sandbox; whoever picks this up with a working `bundle` should run the real migration and let it regenerate schema.rb instead)

**Background:** One row per synthesis request — audit trail of what facts went in, what came out, whether the LLM or the fallback produced it, and how long it took. Lets the dashboard show synthesis history without re-calling the LLM.

- [ ] **Step 1: Migration**

```ruby
# frozen_string_literal: true

class CreateResearchContextSyntheses < ActiveRecord::Migration[7.1]
  def change
    create_table :research_context_syntheses do |t|
      t.jsonb    :facts_payload,   null: false, default: {}
      t.jsonb    :target_context
      t.text     :narrative
      t.string   :source,          null: false, default: "llm" # llm | fallback
      t.string   :model_used
      t.string   :status,          null: false, default: "pending" # pending | completed | failed
      t.string   :error_message
      t.integer  :duration_ms

      t.timestamps
    end

    add_index :research_context_syntheses, :created_at
  end
end
```

- [ ] **Step 2: Model**

```ruby
# frozen_string_literal: true

module Research
  class ContextSynthesis < ApplicationRecord
    self.table_name = "research_context_syntheses"

    STATUSES = %w[pending completed failed].freeze
    SOURCES = %w[llm fallback].freeze

    validates :status, inclusion: { in: STATUSES }
    validates :source, inclusion: { in: SOURCES }
  end
end
```

---

## Chunk 3: LLM Orchestration

### Task 4: `Research::ContextSynthesizerService` — the actual call + fallback

**Files:**
- Create: `app/services/research/context_synthesizer_service.rb`
- Test: `spec/services/research/context_synthesizer_service_spec.rb` (stub `Services::Ai::OllamaClient.instance` — never hit real Ollama in specs)

**Background:** Ties Chunk 1's pure builders to `Services::Ai::OllamaClient`, with the same timeout + sanity-check + deterministic-fallback shape already proven in `agent_runner.rb`. Persists a `Research::ContextSynthesis` row either way so a timeout/failure is visible in the UI (not silently swallowed).

- [ ] **Step 1: Write the service**

```ruby
# frozen_string_literal: true

module Research
  class ContextSynthesizerService < ApplicationService
    TIMEOUT_SECONDS = ENV.fetch("AI_CONTEXT_SYNTHESIS_TIMEOUT", "20").to_i
    MIN_NARRATIVE_LENGTH = 30

    def initialize(buckets:, target_context: nil)
      @buckets = buckets
      @target_context = target_context
    end

    def call
      facts = Research::ContextSynthesizer.build(buckets: @buckets, target_context: @target_context)
      started_at = Time.current

      narrative, source, model = synthesize(facts)

      Research::ContextSynthesis.create!(
        facts_payload: facts, target_context: @target_context, narrative: narrative,
        source: source, model_used: model, status: "completed",
        duration_ms: ((Time.current - started_at) * 1000).round
      )
    rescue StandardError => e
      Rails.logger.error("[Research::ContextSynthesizerService] #{e.class}: #{e.message}")
      Research::ContextSynthesis.create!(
        facts_payload: facts || {}, target_context: @target_context, status: "failed", error_message: e.message
      )
    end

    private

    def synthesize(facts)
      messages = [
        { role: "system", content: Research::SynthesisPromptBuilder.system_prompt },
        { role: "user", content: Research::SynthesisPromptBuilder.user_prompt(facts) }
      ]

      response = Timeout.timeout(TIMEOUT_SECONDS) do
        Services::Ai::OllamaClient.instance.chat(messages: messages, temperature: 0.3,
                                                  log_context: "research_context_synthesis")
      end
      narrative = extract_text(response)

      return [narrative, "llm", response.respond_to?(:model) ? response.model : nil] if valid?(narrative)

      [fallback_narrative(facts), "fallback", nil]
    rescue Timeout::Error, StandardError => e
      Rails.logger.warn("[Research::ContextSynthesizerService] LLM call failed, using fallback: #{e.message}")
      [fallback_narrative(facts), "fallback", nil]
    end

    def valid?(text)
      text.present? && text.length >= MIN_NARRATIVE_LENGTH
    end

    # Deterministic, always-available narrative — the UI must never show
    # nothing just because the LLM was slow or unavailable.
    def fallback_narrative(facts)
      best = facts["best_bucket"]
      worst = facts["worst_bucket"]
      return "Not enough historical sessions analyzed yet to summarize." if best.nil?

      "Across #{facts['total_sessions_analyzed']} sessions in #{facts['total_buckets']} context buckets, " \
        "the best-performing context averaged #{best[:avg_return_pct] || best['avg_return_pct']}% peak return " \
        "(#{best[:sample_size] || best['sample_size']} sessions), while the worst averaged " \
        "#{worst[:avg_return_pct] || worst['avg_return_pct']}%."
    end

    def extract_text(response)
      # Adapt to whatever Services::Ai::OllamaClient#chat actually returns —
      # check its return shape (likely response.dig(:message, :content) or
      # similar) against lib/services/ai/technical_analysis_agent/agent_runner.rb's
      # own usage before wiring this for real.
      response.respond_to?(:content) ? response.content : response.to_s
    end
  end
end
```

> **Implementer note:** the exact shape of `Services::Ai::OllamaClient#chat`'s return value wasn't nailed down during planning — re-check `lib/services/ai/technical_analysis_agent/agent_runner.rb`'s own call site for the real accessor (`.content`, `.dig(:message, :content)`, etc.) before wiring `extract_text` for real, and update the `respond_to?(:content)` guess above.

- [ ] **Step 2: Spec it** — three cases: LLM returns a valid narrative (persists `source: "llm"`), LLM raises/times out (persists `source: "fallback"`, narrative still present), LLM returns too-short/garbage text (falls back even though the call itself "succeeded"). Stub `Services::Ai::OllamaClient.instance` — do not hit real Ollama.

---

## Chunk 4: API

### Task 5: `Api::Research::ContextSynthesesController`

**Files:**
- Create: `app/controllers/api/research/context_syntheses_controller.rb`
- Update: `config/routes.rb`
- Test: `spec/requests/api/research/context_syntheses_spec.rb`

**Background:** `create` runs the same `expectancy_scope` + `Research::ExpectancyReport.call` the existing `expectancy` action already builds (extract that into a shared private method or a small `Research::ExpectancyQuery` helper so it isn't duplicated between the two controller actions), then calls `Research::ContextSynthesizerService.call`. `index`/`show` just list/read persisted `Research::ContextSynthesis` rows (cheap, no LLM call) so the dashboard can show history without re-synthesizing.

- [ ] **Step 1: Routes**

```ruby
namespace :research do
  resources :signals, only: %i[index show create]
  resources :lifecycles, only: %i[index show] do
    collection do
      post :run
      get :expectancy
    end
  end
  resources :context_syntheses, only: %i[index show create] # POST create = "synthesize now"
end
```

- [ ] **Step 2: Controller**

```ruby
# frozen_string_literal: true

module Api
  module Research
    class ContextSynthesesController < ApplicationController
      include Api::TokenAuthenticatable
      include Api::Research::Paginatable

      before_action :authenticate_dashboard_token!

      def index
        records, meta = paginate(::Research::ContextSynthesis.order(created_at: :desc))
        render json: { syntheses: records.map { |s| serialize(s) }, meta: meta }
      end

      def show
        render json: { synthesis: serialize(::Research::ContextSynthesis.find(params[:id])) }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "not_found" }, status: :not_found
      end

      def create
        dimensions = params[:dimensions].presence&.split(",")&.map(&:strip) ||
                     ::Research::ExpectancyReport::DEFAULT_DIMENSIONS
        phase = params[:phase].presence || "entry"
        buckets = ::Research::ExpectancyReport.call(scope: expectancy_scope, dimensions: dimensions, phase: phase)

        synthesis = ::Research::ContextSynthesizerService.call(buckets: buckets, target_context: params[:target_context])
        render json: { synthesis: serialize(synthesis) }, status: :created
      rescue ArgumentError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      # TODO: extract this + Api::Research::LifecyclesController#expectancy_scope into one
      # shared private method (e.g. a small concern) once both exist — don't duplicate the
      # symbol/expiry_flag/option_type/date_from/date_to filter parsing twice.
      def expectancy_scope
        # ... same as Api::Research::LifecyclesController#expectancy_scope
      end

      def serialize(synthesis)
        {
          id: synthesis.id, narrative: synthesis.narrative, source: synthesis.source,
          model_used: synthesis.model_used, status: synthesis.status, error_message: synthesis.error_message,
          duration_ms: synthesis.duration_ms, facts_payload: synthesis.facts_payload,
          target_context: synthesis.target_context, created_at: synthesis.created_at&.iso8601
        }
      end
    end
  end
end
```

- [ ] **Step 3: Specs** — stub `Research::ContextSynthesizerService.call`, assert routing/params/serialization; a separate spec exercises the service itself (Chunk 3).

---

## Chunk 5: Dashboard UI

### Task 6: "Synthesize" on the Context → Expectancy panel

**Files:**
- Update: `dashboard/src/components/research/ExpectancyReportPanel.jsx`

**Background:** After buckets load, add a "Synthesize" button that `POST`s to `/api/research/context_syntheses` with the same `dimensions`/`phase`/filter params already in local state, then renders the narrative in a card below the table with a loading spinner (up to ~20s) and a small badge indicating `llm` vs `fallback` source so users know when the model didn't actually run.

- [ ] **Step 1:** add `narrativeLoading`/`narrative` signals, a `synthesize()` async function mirroring `runReport()`'s fetch pattern, and a card:

```jsx
<Show when={narrative()}>
  <div class="glass rounded-2xl border border-white/5 px-6 py-4">
    <div class="flex items-center justify-between mb-2">
      <h3 class="text-xs font-black text-white uppercase tracking-widest">AI Synthesis</h3>
      <Badge variant={narrative().source === 'llm' ? 'success' : 'outline'} class="text-[9px] uppercase">
        {narrative().source === 'llm' ? narrative().model_used || 'model' : 'fallback (no model)'}
      </Badge>
    </div>
    <p class="text-sm text-gray-300 leading-relaxed">{narrative().narrative}</p>
  </div>
</Show>
```

- [ ] **Step 2:** manual smoke test against a running Rails server + Ollama (or force the fallback path by pointing `OLLAMA_LOCAL_URL` at nothing, to confirm the UI still renders something sane).

---

## Chunk 6: Docs

- [ ] Add a short section to `CLAUDE.md`'s Research Pipeline block once implemented, mirroring the existing `Research::ExpectancyReport` paragraph.
- [ ] Note in the PR/commit description that this is narration-only — it must never be wired into any live entry/exit decision (keeps it unambiguously inside the "offline research" boundary the rest of `Research::` already respects).

---

## Open Questions For Whoever Implements This

1. **`target_context` source in the UI** — should the "Synthesize" button default to summarizing the whole report (no target), or should it default to comparing against *today's live context* (fetched via `Research::ContextClassifier.classify` on the current `Candles::Record` series, same as `Research::UnderlyingContextSnapshot.at(symbol:, timestamp: Time.current)`)? The plan above supports both — `target_context` is just an optional param — but the default UX behavior wasn't decided.
2. **Model choice/temperature** — `temperature: 0.3` above is a guess for "summarize facts faithfully" (lower = less creative/less likely to invent numbers); revisit once you can actually observe outputs.
3. **Rate limiting** — if this button gets clicked repeatedly, each click is a real LLM call; consider a short per-session throttle if it becomes a problem (not built here — YAGNI until observed).
