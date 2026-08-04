# frozen_string_literal: true

Rails.application.routes.draw do
  # Agent dashboard exposes prompts/responses/costs — keep off production unless explicitly enabled.
  if !Rails.env.production? || ENV['ENABLE_AGENTS_DASHBOARD'] == 'true'
    mount RubyLLM::Agents::Engine => "/agents"
  end
  # OpenAPI UI + served spec (disable in production unless ENABLE_SWAGGER_UI=true)
  if !Rails.env.production? || ENV['ENABLE_SWAGGER_UI'] == 'true'
    mount Rswag::Ui::Engine => '/api-docs'
    mount Rswag::Api::Engine => '/api-docs'
  end

  get '/healthz', to: 'health#live'
  get '/ready', to: 'health#ready'

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Optional SMC decision endpoint (non-namespaced controller by design)
  get "smc/decision", to: "smc#decision"

  namespace :api do
    get :health, to: "health#show"
    post :test_broadcast, to: "test#broadcast"
    get :dashboard, to: "dashboard#show"
    get "public_ip/audit", to: "public_ip#audit"
    get :positions, to: "positions#index"
    get :signals,   to: "signals#index"

    get 'market/vix', to: 'market#vix'

    # Live AI analysis dashboard
    get  'analysis/:index_key',            to: 'analysis#show',        as: :analysis
    get  'analysis/:index_key/historical', to: 'analysis#historical',  as: :analysis_historical
    get  'analysis/:index_key/risk_explorer', to: 'analysis#risk_explorer', as: :analysis_risk_explorer
    post 'analysis/:index_key/ai_snapshot', to: 'analysis#ai_snapshot', as: :analysis_ai_snapshot
    post 'analysis/:index_key/optimize',    to: 'analysis#optimize',    as: :analysis_optimize

    # Algo Settings
    get    'settings',           to: 'settings#index'
    patch  'settings/bulk',      to: 'settings#update_bulk'
    post   'settings/update_ip', to: 'settings#update_ip'

    resources :calibration_runs, only: %i[index show] do
      post :apply, on: :member
    end

    # Alpha Engine
    namespace :alpha do
      get  :status
      post :scan
      post :execute
      get  :history
      get  :performance
    end

    # Ledger (paper double-entry)
    get  'ledger/balance', to: 'ledger#balance'
    get  'ledger/journal', to: 'ledger#journal'
    get  'ledger/positions/:id', to: 'ledger#position'

    # Ledger (paper double-entry)
    get  'ledger/balance', to: 'ledger#balance'
    get  'ledger/journal', to: 'ledger#journal'
    get  'ledger/positions/:id', to: 'ledger#position'

    # Circuit breaker — emergency halt
    resource :circuit_breaker, only: %i[show], controller: 'circuit_breaker' do
      post :trip, on: :member
      delete :trip, action: :reset, on: :member
    end

    resource :drawdown_guard, only: [], controller: 'drawdown_guard' do
      delete :reset, on: :member
    end
  end

  # Redis UI (development only)
  if Rails.env.development?
    get 'redis_ui', to: 'redis_ui#index'
    get 'redis_ui/info', to: 'redis_ui#info'
    get 'redis_ui/:id', to: 'redis_ui#show', as: :redis_ui_key
    delete 'redis_ui/:id', to: 'redis_ui#destroy'
  end

  # Quietly handle browser/devtools well-known probes with 204 No Content
  get "/.well-known/*path", to: proc { [204, { "Content-Type" => "text/plain" }, [""]] }
end
