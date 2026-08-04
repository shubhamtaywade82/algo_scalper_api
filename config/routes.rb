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

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # ActionCable WebSocket endpoint
  mount ActionCable.server => '/cable'

  # Legacy SMC path → canonical /api/smc/decision (301, query string preserved)
  get 'smc/decision', to: proc { |env|
    qs = env['QUERY_STRING'].to_s
    loc = qs.present? ? "/api/smc/decision?#{qs}" : '/api/smc/decision'
    [301, { 'Location' => loc, 'Content-Type' => 'text/plain' }, []]
  }

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
    get    'settings', to: 'settings#index'
    get    'settings/fast_entry_mode', to: 'settings#fast_entry_mode'
    patch  'settings/fast_entry_mode', to: 'settings#update_fast_entry_mode'
    get    'settings/change_logs',  to: 'settings#change_logs'
    patch  'settings/bulk',         to: 'settings#update_bulk'
    patch  'settings/deep_merge',   to: 'settings#update_deep_merge'
    post   'settings/update_ip',    to: 'settings#update_ip'

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

    # Circuit breaker — emergency halt
    resource :circuit_breaker, only: %i[show], controller: 'circuit_breaker' do
      post :trip, on: :member
      delete :trip, action: :reset, on: :member
    end

    # Trading Strategies (Strategy Creator)
    resources :trading_strategies, only: %i[index show create update destroy] do
      member do
        post :validate
        post :deploy
      end
    end

    resource :drawdown_guard, only: [], controller: 'drawdown_guard' do
      delete :reset, on: :member
    end

    # Strategy Platform (Phases 2–5)
    resources :strategies, param: :slug, only: %i[index show create] do
      member do
        post :deploy
        post :start
        post :stop
        post :restart
        get  :versions
        get  :signals
        get  :logs
        get  :variables
        put  :variables, action: :update_variables
      end
    end

    # Global platform variables
    get  'variables', to: 'variables#index'
    put  'variables', to: 'variables#update'

    # Strategy subsystem health
    get  'strategies/health/pool',     to: 'strategies/health#pool'
    get  'strategies/health/session',  to: 'strategies/health#session'
    get  'strategies/health/backtest', to: 'strategies/health#backtest'

    # Research pipeline (offline — signal/candidate backtests + premium lifecycle board)
    namespace :research do
      resources :signals, only: %i[index show create]
      resources :lifecycles, only: %i[index show] do
        collection do
          post :run
          get :expectancy
        end
      end
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
