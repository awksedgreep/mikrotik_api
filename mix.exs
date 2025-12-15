defmodule MikrotikApi.MixProject do
  use Mix.Project

  def project do
    [
      app: :mikrotik_api,
      version: "0.3.3",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: [
        description: "Elixir client for MikroTik RouterOS API.",
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/mcotner/mikrotik_api"}
      ],
      source_url: "https://github.com/awksedgreep/mikrotik_api",
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "rest_api.md",
          "livebook/01_quickstart.livemd",
          "livebook/02_auth_and_tls.livemd",
          "livebook/03_crud_basics.livemd",
          "livebook/04_ensure_workflows.livemd",
          "livebook/05_multi_and_probe.livemd",
          "livebook/06_dns_and_users.livemd"
        ],
        groups_for_extras: [
          Livebooks: ~r{^livebook/}
        ],
        source_ref: "v0.3.2"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
