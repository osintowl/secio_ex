defmodule SecioEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :secio_ex,
      version: "0.2.0",
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
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:plug, "~> 1.15", only: :test},
      {:req, "~> 0.5 or ~> 0.6 or ~> 0.7"}
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
