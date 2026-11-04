Rails.application.routes.draw do
  mount Busbar::Engine, at: "/busbar"
end
