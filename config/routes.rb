Rails.application.routes.draw do
  resources :home, only: [:index], path: '' do
    member do
      get :phone_finder, path: 'phone-finder'
    end
  end

  root 'home#index'
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
