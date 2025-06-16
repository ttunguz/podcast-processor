Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Define routes for processed podcasts
  # List all processed podcasts
  get "processed_podcasts", to: "processed_podcasts#index", as: :processed_podcasts
  # Show a specific podcast summary, using the filename as ID
  get "processed_podcasts/:filename", to: "processed_podcasts#show", as: :processed_podcast, constraints: { filename: /[^\/]+/ } # Allow dots in filename

  # Defines the root path route ("/")
  # root "posts#index"
  # Set the root path to the processed podcasts list
  root "processed_podcasts#index"

end 