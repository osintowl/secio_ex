defmodule SecioEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :secio_ex,
      version: "0.2.1",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: "A library for interacting with sec-api.io"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl],
      mod: {SecioEx.Application, []}
    ]
  end

  defp deps do
    [
      {:websockex, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:finch, "~> 0.21"},
      # Mint 1.10.2 and hpax 1.0.4 are the first releases that close the
      # HTTP/1 and HPACK advisories. Finch 0.21 still allows older releases.
      {:mint, ">= 1.10.2 and < 2.0.0"},
      {:hpax, ">= 1.0.4 and < 2.0.0"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:plug, ">= 1.20.4 and < 2.0.0", only: :test},
      {:plug_crypto, ">= 2.2.1 and < 3.0.0", only: :test},
      # Req 0.6.1 turns off automatic archive extraction and compression.
      # 0.7 stays allowed. 0.5 and 0.6.0 do not.
      {:req, "~> 0.6.1 or ~> 0.7.0"}
    ]
  end

  defp package do
    [
      files: ~w(lib priv .formatter.exs mix.exs LICENSE*),
      licenses: ["BSD-3-Clause"],
      links: %{"GitHub" => "https://github.com/osintowl/secio_ex"}
    ]
  end
end
