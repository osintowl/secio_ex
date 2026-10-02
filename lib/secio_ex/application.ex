defmodule SecioEx.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Finch, name: SecioEx.Finch, pools: %{default: [size: 32, pool_max_idle_time: 60_000]}}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: SecioEx.Supervisor)
  end
end
