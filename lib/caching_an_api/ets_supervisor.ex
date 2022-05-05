defmodule Ets.Supervisor do
  use Supervisor
  require EtsDb

  def start_link(name) do
    Supervisor.start_link(__MODULE__, name, name: __MODULE__)
  end

  @impl true
  def init(name) do
    [
      {EtsDb, name}
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end
end
