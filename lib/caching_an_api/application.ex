defmodule CachingAnApi.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    topologies = Application.get_env(:libcluster, :topologies) || []

    opts = [strategy: :one_for_one, name: CachingAnApi.Supervisor]

    cache_opt = [
      store: :mn,
      cache_on: true,
      mn_table: :mcache,
      ets_table: :ecache
    ]

    # list to be supervised
    [
      # start the cache
      {Cache, cache_opt},
      # start libcluster
      {Cluster.Supervisor, [topologies, [name: CachingAnApi.ClusterSupervisor]]}
    ]
    |> Supervisor.start_link(opts)
  end
end
