Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "home#index"

  namespace :api do
    get :health, to: "health#show"
    post :test_broadcast, to: "test#broadcast"
    get :atm_options, to: "atm_options#index"

    # Paper trading observability endpoints (only enabled when PAPER_MODE=true)
    namespace :paper do
      # New state controller endpoints (V2)
      get :wallet, to: "state#wallet"
      get :position, to: "state#position"
      get :fills, to: "state#fills"
      get :performance, to: "state#performance"

      # Legacy endpoints (kept for backward compatibility if any clients use them)
      # get :orders, to: "paper#orders"
    end
  end

  # Quietly handle browser/devtools well-known probes with 204 No Content
  get "/.well-known/*path", to: proc { [ 204, { "Content-Type" => "text/plain" }, [ "" ] ] }

  mount ActionCable.server => "/cable"
end
