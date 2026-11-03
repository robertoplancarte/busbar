Busbar::Engine.routes.draw do
  resources :runs, only: %i[index new create show] do
    resource :mapping, only: %i[show update]
    resource :review, only: %i[show update]
    member do
      post :cancel
      post :rerun_after_ingestion
    end
  end
  root to: "runs#index"
end
