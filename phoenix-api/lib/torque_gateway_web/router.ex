defmodule TorqueGatewayWeb.Router do
  use TorqueGatewayWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :jwt_required do
    plug TorqueGatewayWeb.Plugs.Authenticate
  end

  scope "/api", TorqueGatewayWeb do
    pipe_through :api

    post "/auth/signup", AuthController, :signup
    post "/auth/signin", AuthController, :signin
    post "/auth/refresh", AuthController, :refresh
    post "/auth/reset/request", AuthController, :reset_request
    post "/auth/reset/confirm", AuthController, :reset_confirm

    get "/stores", StoreController, :index
    get "/mods", ModController, :index
    get "/mods/:id", ModController, :show
  end

  scope "/api", TorqueGatewayWeb do
    pipe_through [:api, :jwt_required]

    delete "/auth/signout", AuthController, :signout
    get "/profile/me", ProfileController, :me
    put "/profile/me", ProfileController, :update_me
  end
end
