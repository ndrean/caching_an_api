defmodule Cache.Supervisor do
  use Supervisor

  def start_link(init_args) do
    Supervisor.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  @impl true
  def init(init_args) do
    [
      {Cache, init_args}
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end
end
