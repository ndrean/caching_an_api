defmodule CacheGS.Supervisor do
  @moduledoc """
  With `:transient`, the child process is restarted only if it terminates abnormally, i.e., with an exit reason other than :normal, :shutdown, or {:shutdown, term}.
  """
  use Supervisor, restart: :transient

  def start_link(init_args) do
    Supervisor.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  @impl true
  def init(init_args) do
    [
      {CacheGS, init_args}
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end
end
