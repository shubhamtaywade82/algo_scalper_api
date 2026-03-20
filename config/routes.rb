# frozen_string_literal: true

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # ActionCable WebSocket endpoint
  mount ActionCable.server => '/cable'

  # Optional SMC decision endpoint (non-namespaced controller by design)
  get "smc/decision", to: "smc#decision"

  namespace :api do
    get :health, to: "health#show"
    post :test_broadcast, to: "test#broadcast"
    get :dashboard, to: "dashboard#show"
    get :positions, to: "positions#index"

    # Live AI analysis dashboard
    get  'analysis/:index_key',            to: 'analysis#show',        as: :analysis
    get  'analysis/:index_key/historical', to: 'analysis#historical',  as: :analysis_historical
    post 'analysis/:index_key/ai_snapshot', to: 'analysis#ai_snapshot', as: :analysis_ai_snapshot

    # Algo Settings
    get    'settings',      to: 'settings#index'
    patch  'settings/bulk', to: 'settings#update_bulk'

    # Calibration runs — view and apply automated config patches
    resources :calibration_runs, only: %i[index show] do
      member do
        post :apply
      end
    end

    # Circuit breaker — emergency halt
    # GET    /api/circuit_breaker        → status (unauthenticated)
    # POST   /api/circuit_breaker/trip   → trip   (requires X-Circuit-Breaker-Token)
    # DELETE /api/circuit_breaker/trip   → reset  (requires X-Circuit-Breaker-Token)
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
