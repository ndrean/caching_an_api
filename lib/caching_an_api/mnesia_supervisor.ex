defmodule MnDb.Supervisor do
  use Supervisor

  # https://github.com/beardedeagle/mnesiac/blob/master/lib/mnesiac/supervisor.ex

  def start_link(init_args) do
    Supervisor.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  @impl true
  def init(init_args) do
    [
      {MnDb, init_args}
    ]
    |> Supervisor.init(strategy: :one_for_one)

    # Mnesiac.init_mnesia(config)
    # Supervisor.init([], opts)
  end
end
