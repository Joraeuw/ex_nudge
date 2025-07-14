defmodule ExampleExNudge.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ExampleExNudgeWeb.Telemetry,
      ExampleExNudge.Repo,
      {DNSCluster, query: Application.get_env(:example_ex_nudge, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ExampleExNudge.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: ExampleExNudge.Finch},
      # Start a worker by calling: ExampleExNudge.Worker.start_link(arg)
      # {ExampleExNudge.Worker, arg},
      # Start to serve requests, typically the last entry
      ExampleExNudgeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExampleExNudge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ExampleExNudgeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
