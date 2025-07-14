defmodule ExampleExNudge.Repo do
  use Ecto.Repo,
    otp_app: :example_ex_nudge,
    adapter: Ecto.Adapters.Postgres
end
