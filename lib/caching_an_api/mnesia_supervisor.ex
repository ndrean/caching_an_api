defmodule Mndb.Supervisor do
  use Supervisor
  require Logger
  # https://github.com/beardedeagle/mnesiac/blob/master/lib/mnesiac/supervisor.ex

  def start_link(init_args) do
    Supervisor.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  @impl true
  def init(init_args) do
    [
      {Mndb, init_args}
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end
end
