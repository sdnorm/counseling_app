Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resources :users, only: [ :new, :create ]

  namespace :api do
    resource :sync, only: [ :show, :update ], controller: "sync" do
      post :reset
    end
    resource :push, only: [ :create, :destroy ], controller: "push"
    get "push/vapid_public_key", to: "push#vapid_public_key"
    patch "push/preferences", to: "push#update_preferences"
  end

  namespace :admin do
    resources :invites, only: [ :index, :create ]
  end

  get "up" => "rails/health#show", as: :rails_health_check
  get "/screens/:id", to: "screens#show", as: :screen

  root "home#index"
end
