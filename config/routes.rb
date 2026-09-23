Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resources :users, only: [ :new, :create ]
  get "/manifest.json", to: "manifests#show", as: :manifest
  post "/stripe/webhooks", to: "stripe/webhooks#create", as: :stripe_webhooks

  namespace :api do
    resource :account_keys, only: [ :show, :update ], path: "account/keys"
    resource :sync, only: [ :show, :update ], controller: "sync"
    resource :push, only: [ :create, :destroy ], controller: "push"
    get "push/vapid_public_key", to: "push#vapid_public_key"
    patch "push/preferences", to: "push#update_preferences"
  end

  namespace :counselor, module: "dashboard" do
    root "clients#index"
    resource :session, only: [ :new, :create, :destroy ]
    resources :passwords, param: :token, only: [ :new, :create, :edit, :update ]
    get  "setup/:token", to: "setups#show",   as: :setup
    post "setup/:token", to: "setups#create"
    resources :clients, only: [ :index ] do
      member do
        patch :archive
        patch :unarchive
      end
    end
    resources :invites, only: [ :index, :create ]
    resource :practice, only: [ :edit, :update ]
    resources :members, only: [ :index, :create, :destroy ]
    resource :account, only: [ :edit, :update ]
    resource :billing, only: [ :show ] do
      post :checkout
      post :portal
    end
  end

  namespace :platform do
    root "practices#index"
    resources :practices, only: [ :index, :show, :update ]
    resources :practice_invites, only: [ :new, :create, :show ]
  end

  get "up" => "rails/health#show", as: :rails_health_check
  get "/screens/:id", to: "screens#show", as: :screen

  root "home#index"
end
