import Config

config :torque_gateway,
  ecto_repos: [TorqueGateway.Repo],
  cache_ttl_ms: 60_000,
  rust_service: [base_url: "http://localhost:3001"],
  access_token_ttl_secs: 3600,
  refresh_token_ttl_secs: 60 * 60 * 24 * 30,
  reset_token_ttl_secs: 60 * 60,
  jwt_issuer: "torque_gateway",
  jwt_secret: "dev_jwt_secret_change_me",
  mailer: TorqueGateway.Mailer.Log,
  log_password_reset_tokens: false,
  password_reset_url_base: "torqueindex://reset?token=",
  store_registry: [
    %{
      id: "21overlays",
      name: "21 Overlays",
      base_url: "https://21overlays.com.au",
      logo_url: "/store_logos/21overlays.png"
    },
    %{
      id: "dubhaus",
      name: "Dubhaus",
      base_url: "https://dubhaus.com.au",
      logo_url:
        "https://dubhaus.com.au/cdn/shop/files/Dubhaus-Logo-Dark_2x_aceaf8af-66d7-4aa4-9bdc-e7b868f4752b.png?v=1677123947&width=2000"
    },
    %{
      id: "modeautoconcepts",
      name: "Mode Auto Concepts",
      base_url: "https://modeautoconcepts.com",
      logo_url: "https://modeautoconcepts.com/cdn/shop/files/mode_website_header.png?v=1726554561&width=130"
    },
    %{
      id: "xforce",
      name: "XForce",
      base_url: "https://xforce.com.au",
      logo_url: "https://xforce.com.au/cdn/shop/files/Logo_Square_X_RED.png?v=1754529662"
    },
    %{
      id: "justjap",
      name: "JustJap",
      base_url: "https://justjap.com",
      logo_url: "https://justjap.com/cdn/shop/t/76/assets/icon-logo.svg?v=158336173239139661481733262283"
    },
    %{
      id: "modsdirect",
      name: "Mods Direct",
      base_url: "https://www.modsdirect.com.au",
      logo_url: "https://www.modsdirect.com.au/cdn/shop/files/MODSPPFBLK.png?v=1717205712&width=520"
    },
    %{
      id: "prospeedracing",
      name: "Prospeed Racing",
      base_url: "https://www.prospeedracing.com.au",
      logo_url: "https://www.prospeedracing.com.au/cdn/shop/files/pro_speed_racing_logo.png?v=1702293418&width=340"
    },
    %{
      id: "shiftymods",
      name: "Shifty Mods",
      base_url: "https://shiftymods.com.au",
      logo_url: "https://shiftymods.com.au/cdn/shop/files/3.png?v=1724340298&width=275"
    },
    %{
      id: "hi-torqueperformance",
      name: "Hi-Torque Performance",
      base_url: "https://hi-torqueperformance.myshopify.com",
      logo_url: "https://hi-torqueperformance.myshopify.com/cdn/shop/files/HTP_logo_300x300.png?v=1751503487"
    },
    %{
      id: "performancewarehouse",
      name: "Performance Warehouse",
      base_url: "https://performancewarehouse.com.au",
      logo_url: "https://cdn.shopify.com/s/files/1/0323/1596/5572/files/main-logo-v4.png?v=1707862321"
    },
    %{
      id: "streetelement",
      name: "Street Element",
      base_url: "https://streetelement.com.au",
      logo_url: "/store_logos/streetelement.png"
    },
    %{
      id: "allautomotiveparts",
      name: "All Automotive Parts",
      base_url: "https://allautomotiveparts.com.au",
      logo_url: "https://allautomotiveparts.com.au/cdn/shop/files/logo_3.png?v=1662423972&width=438"
    },
    %{
      id: "eziautoparts",
      name: "Ezi Auto Parts",
      base_url: "https://eziautoparts.com.au",
      logo_url: "https://eziautoparts.com.au/cdn/shop/files/eziauto_logo_white_inlay.png?v=1711271402&width=600"
    },
    %{
      id: "autocave",
      name: "Auto Cave",
      base_url: "https://autocave.com.au",
      logo_url:
        "https://autocave.com.au/cdn/shop/files/Untitled_design_-_2024-12-09T203629.178_300x@2x.png?v=1733736998"
    },
    %{
      id: "jtmauto",
      name: "JTM Auto",
      base_url: "https://jtmauto.com.au",
      logo_url: "https://jtmauto.com.au/cdn/shop/files/jtm-logo4_456x60.png?v=1704599783"
    },
    %{
      id: "tjautoparts",
      name: "TJ Auto Parts",
      base_url: "https://tjautoparts.com.au",
      logo_url: "https://tjautoparts.com.au/cdn/shop/files/Logo-01_Crop_393x150.png?v=1711854530"
    },
    %{
      id: "nationwideautoparts",
      name: "Nationwide Auto Parts",
      base_url: "https://www.nationwideautoparts.com.au",
      logo_url: "https://www.nationwideautoparts.com.au/cdn/shop/files/NW-Logo-Temp_200x50.png?v=1745620530"
    },
    %{
      id: "chicaneaustralia",
      name: "Chicane Australia",
      base_url: "https://www.chicaneaustralia.com.au",
      logo_url:
        "https://www.chicaneaustralia.com.au/cdn/shop/files/ChicaneLogo_2048x2048-LockupWhiteTransparent_V1.png?v=1747808484&width=300"
    }
  ]

config :torque_gateway, TorqueGateway.Repo,
  migration_primary_key: [name: :id, type: :binary_id],
  migration_foreign_key: [type: :binary_id]

config :torque_gateway, TorqueGatewayWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [json: TorqueGatewayWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TorqueGateway.PubSub,
  check_origin: false

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
