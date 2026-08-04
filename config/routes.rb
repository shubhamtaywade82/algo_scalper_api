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
