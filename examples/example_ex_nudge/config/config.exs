# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :example_ex_nudge,
  ecto_repos: [ExampleExNudge.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :example_ex_nudge, ExampleExNudgeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ExampleExNudgeWeb.ErrorHTML, json: ExampleExNudgeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ExampleExNudge.PubSub,
  live_view: [signing_salt: "lGKDloty"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :example_ex_nudge, ExampleExNudge.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  example_ex_nudge: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  example_ex_nudge: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :ex_nudge,
  vapid_subject: "mailto:user@example.com",
  vapid_public_key:
    "BNZZpbaklEna0msW6sw8rLbQLg8QH__6ZLIswkAcAXIbMG9K_lAU7WP8GyMO2rirfdGRAXZOJgX6rxT6bsJFySI",
  vapid_private_key: "WKSxLqHCgGocrF1iC62oprJKQrcS4ELE1bo-Pw_UljQ"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
