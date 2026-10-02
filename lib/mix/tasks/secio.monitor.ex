defmodule Mix.Tasks.Secio.Monitor do
  use Mix.Task

  @shortdoc "Watch SEC filings as they are accepted by EDGAR"

  @moduledoc """
  Live monitor for the sec-api.io filing stream.

      mix secio.monitor
      mix secio.monitor --forms 8-K,4 --watch AAPL,MSFT
      mix secio.monitor --plain --for 30
      mix secio.monitor --json --forms 8-K

  The API key is read from `--api-key-file`, `SEC_API_KEY`, or `~/Desktop/sec.txt`.

  8-K item 1.05 (material cybersecurity incident) is critical, with bankruptcy
  (1.03), restatement (4.02), delisting (3.01), and change in control (5.01).

  In the dashboard:

      q quit    a alerts-only    p pause    w watch-only
      j older   k newer          r back to live

  `--forms`, `--tickers`, and `--ciks` limit what is kept. `--watch` highlights
  names without hiding the rest. A form also matches its `/A` amendment.
  """

  @switches [
    forms: :string,
    tickers: :string,
    ciks: :string,
    watch: :string,
    alerts: :boolean,
    plain: :boolean,
    json: :boolean,
    bell: :boolean,
    api_key: :string,
    api_key_file: :string,
    for: :integer
  ]

  @aliases [f: :forms, t: :tickers, w: :watch]

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: @switches, aliases: @aliases)

    if rest != [] or invalid != [] do
      Mix.raise(
        "usage: mix secio.monitor [--forms 8-K,4] [--watch AAPL] [--plain|--json] [--for SECONDS]"
      )
    end

    Mix.Task.run("app.start")

    SecioEx.Monitor.run(
      form_types: opts[:forms],
      tickers: opts[:tickers],
      ciks: opts[:ciks],
      watch: opts[:watch],
      alerts_only: Keyword.get(opts, :alerts, false),
      mode: mode(opts),
      bell: bell(opts),
      api_key: opts[:api_key],
      api_key_file: opts[:api_key_file],
      seconds: opts[:for]
    )
  end

  defp mode(opts) do
    cond do
      opts[:json] -> :json
      opts[:plain] -> :plain
      true -> :auto
    end
  end

  defp bell(opts) do
    cond do
      Keyword.has_key?(opts, :bell) -> opts[:bell]
      opts[:json] -> false
      true -> true
    end
  end
end
