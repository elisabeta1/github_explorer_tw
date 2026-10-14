Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "repositories#index"
  get "repositories", to: "repositories#index", as: :repositories
  # Repo names can contain dots (e.g. vercel/next.js), so no ".json"-style
  # format suffix here. The whitelist keeps the segments to valid GitHub names.
  scope "repositories/:owner/:name", constraints: { owner: /[\w.-]+/, name: /[\w.-]+/ }, format: false do
    get "/", to: "repositories#show", as: :repository
    get "contributors", to: "repositories#contributors", as: :repository_contributors
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
