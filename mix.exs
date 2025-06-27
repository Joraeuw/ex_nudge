defmodule ExNudge.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/joraeuw/ex_nudge"

  def project do
    [
      app: :ex_nudge,
      name: "ExNudge",
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: []
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:httpoison, "~> 2.0"},
      {:jose, "~> 1.11"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false},
      {:bypass, "~> 2.1", only: :test},
      {:mimic, "~> 1.12", only: :test},
      {:excoveralls, "~> 0.16", only: :test}
    ]
  end

  defp description do
    """
    ExNudge is a pure elixir library with the purpose of sending Web Push notifications in compliance with RFC 8291.
    Supports VAPID authentication and payload encryption.
    """
  end

  defp package do
    [
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Docs" => "https://hexdocs.pm/ex_nudge"
      },
      maintainers: ["Zhora Nersisyan <joraeuw@gmail.com>"]
    ]
  end

  defp docs do
    [
      main: "ExNudge",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        Core: [ExNudge, ExNudge.Subscription],
        Encryption: [ExNudge.Encryption],
        Authentication: [ExNudge.VAPID],
        Utilities: [ExNudge.Utils]
      ]
    ]
  end
end
