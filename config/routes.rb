Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    get :health, to: "health#show"
    post :test_broadcast, to: "test#broadcast"

    # Watchlist management
    resources :watchlist, only: [:index, :show, :create, :destroy]

    # Swing trading recommendations
    namespace :swing_trading do
      resources :recommendations, only: [:index, :show] do
        member do
          post :execute
          post :cancel
        end
        collection do
          post 'analyze/:watchlist_item_id', to: 'recommendations#analyze', as: :analyze
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
  get "/.well-known/*path", to: proc { [ 204, { "Content-Type" => "text/plain" }, [ "" ] ] }
end
