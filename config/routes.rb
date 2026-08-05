# frozen_string_literal: true

Rails.application.routes.draw do
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

    get    'settings',              to: 'settings#index'
    get    'settings/change_logs',  to: 'settings#change_logs'
    patch  'settings/bulk',         to: 'settings#update_bulk'

    get 'dashboard', to: 'dashboard#show'
    get 'orders', to: 'orders#index'
    get 'equity_curve', to: 'equity_curve#index'
    resources :positions, only: %i[index show] do
      post :close, on: :member
    end
    resources :alerts, only: %i[index create update destroy]

    get 'signals', to: 'signals#index'
    get 'analysis/:index_key', to: 'analysis#show'
    get 'analysis/:index_key/historical', to: 'analysis#historical'
    post 'analysis/:index_key/ai_snapshot', to: 'analysis#ai_snapshot'
    get 'candles/:index_key', to: 'candles#index'
    get 'option_chain/:index_key', to: 'option_chains#show'
    get 'depth', to: 'depth#index'
    get 'market/vix', to: 'market#vix'
    post 'drawdown_guard/reset', to: 'drawdown_guard#reset'
    get 'public_ip/audit', to: 'public_ip#audit'
    get 'dhan_access_token', to: 'dhan_access_token#show'
    get 'smc/decision', to: 'smc#decision'

    get 'alpha/status', to: 'alpha#status'
    get 'alpha/history', to: 'alpha#history'
    get 'alpha/performance', to: 'alpha#performance'

    get    'ledger/balance',  to: 'ledger#balance'
    get    'ledger/journal',  to: 'ledger#journal'
    get    'ledger/position', to: 'ledger#position'

    get  'funds', to: 'funds#index'
    post 'funds/add', to: 'funds#add'
    post 'funds/withdraw', to: 'funds#withdraw'

    get 'holdings', to: 'holdings#index'
    get 'logs', to: 'logs#index'

    get 'reports', to: 'reports#index'
    get 'reports/pnl', to: 'reports#pnl'
    get 'reports/trades', to: 'reports#trades'
    get 'reports/performance', to: 'reports#performance'
    get 'reports/pnl_by_strategy', to: 'reports#pnl_by_strategy'
    get 'reports/pnl_by_instrument', to: 'reports#pnl_by_instrument'
    get 'reports/export', to: 'reports#export'

    get  'scheduler/tasks', to: 'scheduler#index'
    post 'scheduler/tasks/:id/execute', to: 'scheduler#execute'

    post 'backtests', to: 'backtests#create'
    post 'replays', to: 'replays#create'

    resources :calibration_runs, only: %i[index show] do
      post :apply, on: :member
    end

    get   'variables', to: 'variables#index'
    put   'variables', to: 'variables#update'

    resources :trading_strategies, only: %i[index show create update destroy] do
      post :validate, on: :member
      post :deploy, on: :member
    end

    resources :strategies, only: %i[index show create], param: :slug do
      member do
        post :deploy
        post :start
        post :stop
        post :restart
        get :versions
        get :signals
        get :logs
        get :variables
        put :variables, action: :update_variables
      end
    end
    get 'strategies/health/pool', to: 'strategies/health#pool'
    get 'strategies/health/session', to: 'strategies/health#session'
    get 'strategies/health/backtest', to: 'strategies/health#backtest'

    namespace :research do
      resources :lifecycles, only: %i[index show] do
        collection do
          post :run
          get :expectancy
        end
      end
      resources :signals, only: %i[index show create]
    end

    # Circuit breaker — emergency halt
    # GET    /api/circuit_breaker        → status (unauthenticated)
    # POST   /api/circuit_breaker/trip   → trip   (requires X-Circuit-Breaker-Token)
    # DELETE /api/circuit_breaker/trip   → reset  (requires X-Circuit-Breaker-Token)
    resource :circuit_breaker, only: %i[show], controller: 'circuit_breaker' do
      post :trip, on: :member
      delete :trip, action: :reset, on: :member
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
