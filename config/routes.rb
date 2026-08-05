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
