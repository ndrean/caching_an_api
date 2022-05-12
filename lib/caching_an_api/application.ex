defmodule CachingAnApi.Application do
  @moduledoc false

  use Application
  require Logger
  # require EtsDb

  @impl true
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    topologies = Application.get_env(:libcluster, :topologies) || []
    opts = [strategy: :one_for_one, name: CachingAnApi.Supervisor]

    # cookie = Application.get_env(:caching_an_api, :cookie)
    # Node.set_cookie(cookie)

    cache_opt = [
      store: Application.get_env(:caching_an_api, :store),
      mn_table: Application.get_env(:caching_an_api, :mn_table) || :mcache,
      ets_table: Application.get_env(:caching_an_api, :ets_table) || :ecache,
      disc_copy: Application.get_env(:caching_an_api, :disc_copy) || nil
    ]

    cluster_type = [
      cluster_type:
        Application.get_env(:libcluster, :topologies)[:local_epmd][:strategy] ||
          Application.get_env(:libcluster, :topologies)[:gossip_ex][:strategy]
    ]

    Logger.notice("Config: #{inspect(cache_opt ++ cluster_type)}")

    # start Ets with a table name
    EtsDb.init(cache_opt)

    # list to be supervised
    [
      # start libcluster
      {Cluster.Supervisor, [topologies, [name: CachingAnApi.ClusterSupervisor]]},

      # start Mnesia GenServer
      # {MnDb.Supervisor, cache_opt},

      # start Redis adapter
      {Redix, name: :redix},

      # start Cache GS
      {CacheGS.Supervisor, cache_opt}
      # {CacheA, cache_opt ++ [state: %{}]} <- testing the Agent point of view
    ]
    |> Supervisor.start_link(opts)
  end
end
