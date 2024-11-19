defmodule SecioEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :secio_ex,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: ["lib", "lib/secio_ex"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: "A library for interacting with sec-api.io"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:websockex, "~> 0.4.3"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:req, "~> 0.5.6"}
    ]
  end

  defp package do
    [
      files: ~w(lib priv .formatter.exs mix.exs LICENSE*),
      licenses: ["BSD-3-Clause"],
      links: %{"GitHub" => "https://github.com/nix2intel/secio_ex"}
    ]
  end
end
