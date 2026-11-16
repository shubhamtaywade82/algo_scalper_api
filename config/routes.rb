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
    resource :health, only: :show, controller: 'health'
    resources :test_broadcasts, only: :create

    # Settings: PUT replaces whole top-level sections, PATCH deep-merges a nested patch.
    resource :settings, only: %i[show update]
    scope 'settings', as: 'settings' do
      resources :change_logs, only: :index, controller: 'setting_change_logs'
      resource :fast_entry_mode, only: %i[show update]
      resource :ip_whitelist, only: :update, controller: 'ip_whitelists'
    end

    resource :dashboard, only: :show, controller: 'dashboard'
    resources :orders, only: :index
    resource :equity_curve, only: :show, controller: 'equity_curve'
    resources :positions, only: %i[index show] do
      resource :closure, only: :create, controller: 'position_closures'
      resources :journal_entries, only: :index, controller: 'position_journal_entries'
    end
    resources :alerts, only: %i[index create update destroy]
    resources :signals, only: :index

    resources :analyses, path: 'analysis', param: :index_key, only: :show, controller: 'analysis'
    scope 'analysis/:index_key', as: 'analysis' do
      resource :history, only: :show, controller: 'analysis_histories'
      resources :ai_snapshots, only: :create, controller: 'analysis_ai_snapshots'
    end
    resources :candles, param: :index_key, only: :show
    resources :option_chains, path: 'option_chain', param: :index_key, only: :show
    resource :depth, only: :show, controller: 'depth'
    resource :market_vix, path: 'market/vix', only: :show, controller: 'market_vix'
    resource :public_ip_audit, path: 'public_ip/audit', only: :show
    # Requires API_OPERATOR_TOKEN — never expose this endpoint without that env var set
    resource :dhan_access_token, only: :show, controller: 'dhan_access_token'
    resource :dhan_token, path: 'dhan/token', only: :show
    resource :smc_decision, path: 'smc/decision', only: :show

    scope 'alpha', as: 'alpha' do
      resource :status, only: :show, controller: 'alpha_statuses'
      resources :history, only: :index, controller: 'alpha_signals', as: :signals
      resource :performance, only: :show, controller: 'alpha_performances'
    end

    scope 'ledger', as: 'ledger' do
      resource :balance, only: :show, controller: 'ledger_balances'
      resources :journal, only: :index, controller: 'ledger_journal_entries', as: :journal_entries
    end

    resource :funds, only: :show
    scope 'funds', as: 'funds' do
      resources :deposits, only: :create, controller: 'fund_deposits'
      resources :withdrawals, only: :create, controller: 'fund_withdrawals'
    end

    resources :holdings, only: :index
    resources :logs, only: :index

    scope 'reports', as: 'reports' do
      resource :pnl, only: :show, controller: 'pnl_reports'
      resources :trades, only: :index, controller: 'trade_reports'
      resource :performance, only: :show, controller: 'performance_reports'
      resources :pnl_by_strategy, only: :index, controller: 'strategy_pnl_reports', as: :strategy_pnls
      resources :pnl_by_instrument, only: :index, controller: 'instrument_pnl_reports', as: :instrument_pnls
      resource :export, only: :show, controller: 'report_exports'
      resource :market_brief, only: %i[show create] do
        resource :live, only: :show, controller: 'live_market_briefs'
      end
    end

    scope 'scheduler', as: 'scheduler' do
      resources :tasks, only: :index, controller: 'scheduled_tasks' do
        resources :executions, only: :create, controller: 'scheduled_task_executions'
      end
    end

    resources :backtests, only: %i[create show]
    resources :replays, only: :create
    # GET /api/backtest_runs/:id.csv downloads the trades
    resources :backtest_runs, only: %i[create index show]
    resources :calibration_runs, only: %i[index show] do
      resource :application, only: :create, controller: 'calibration_run_applications'
    end

    resource :variables, only: %i[show update]

    resources :trading_strategies, only: %i[index show create update destroy] do
      resource :validation, only: :create, controller: 'trading_strategy_validations'
      resource :deployment, only: :create, controller: 'trading_strategy_deployments'
    end

    scope 'strategies/health', module: 'strategies', as: 'strategy_health' do
      resource :pool, only: :show, controller: 'health_pools'
      resource :session, only: :show, controller: 'health_sessions'
      resource :backtest, only: :show, controller: 'health_backtests'
    end
    resources :strategies, only: %i[index show create], param: :slug do
      resource :deployment, only: :create, controller: 'strategy_deployments'
      # POST starts, PATCH restarts, DELETE stops the strategy runner
      resource :run, only: %i[create update destroy], controller: 'strategy_runs'
      resources :versions, only: :index, controller: 'strategy_versions'
      resources :signals, only: :index, controller: 'strategy_signals'
      resources :logs, only: :index, controller: 'strategy_logs'
      resource :variables, only: %i[show update], controller: 'strategy_variables'
    end

    namespace :research do
      resource :expectancy, path: 'lifecycles/expectancy', only: :show, controller: 'lifecycle_expectancies'
      resources :lifecycle_runs, only: :create
      resources :lifecycles, only: %i[index show]
      resources :signals, only: %i[index show create]
    end

    namespace :mcp do
      resources :tools, only: :index do
        resources :calls, only: :create, controller: 'tool_calls'
      end
      resources :questions, only: :create
    end

    # Circuit breaker — emergency halt. Trip/reset need X-Circuit-Breaker-Token.
    resource :circuit_breaker, only: :show, controller: 'circuit_breaker' do
      resource :trip, only: %i[create destroy], controller: 'circuit_breaker_trips'
    end
    # Drawdown guard: DELETE clears the day's latched trip (operator token)
    resource :drawdown_guard, only: [] do
      resource :trip, only: :destroy, controller: 'drawdown_guard_trips'
    end
  end

  # Redis UI (development only)
  if Rails.env.development?
    resource :redis_ui_info, path: 'redis_ui/info', only: :show
    resources :redis_ui, only: %i[index show destroy], controller: 'redis_ui', as: :redis_ui_keys
  end

  # Quietly handle browser/devtools well-known probes with 204 No Content
  get "/.well-known/*path", to: proc { [204, { "Content-Type" => "text/plain" }, [""]] }
end
