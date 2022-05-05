defmodule CachingAnApi.Application do
  @moduledoc false

  use Application

  # require EtsDb

  @impl true
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    topologies = Application.get_env(:libcluster, :topologies) || []

    opts = [strategy: :one_for_one, name: CachingAnApi.Supervisor]

    cache_opt = [
      store: Application.get_env(:caching_an_api, :store),
      mn_table: Application.get_env(:caching_an_api, :mn_table),
      ets_table: Application.get_env(:caching_an_api, :ets_table)
    ]

    IO.puts("ici #{cache_opt[:ets_table]}")

    # list to be supervised
    [
      # start libcluster
      {Cluster.Supervisor, [topologies, [name: CachingAnApi.ClusterSupervisor]]},
      {Ets.Supervisor, [ets_table: cache_opt[:ets_table]]},
      # start the cache
      {Cache.Supervisor, cache_opt}

      # %{
      #   id: EtsDb,
      #   start: {EtsDb, :start_link, [[cache_opt[:ets_table]]]}
      # }
    ]
    |> Supervisor.start_link(opts)
  end
end
