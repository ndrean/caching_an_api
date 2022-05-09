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

    cache_opt = [
      store: Application.get_env(:caching_an_api, :store) || :ets,
      mn_table: Application.get_env(:caching_an_api, :mn_table) || :mcache,
      ets_table: Application.get_env(:caching_an_api, :ets_table) || :ecache,
      disc_copy: Application.get_env(:caching_an_api, :disc_copy) || nil
    ]

    mn_opt = [mn_table: cache_opt[:mn_table], disc_copy: cache_opt[:disc_copy]]

    cluster_type =
      Application.get_env(:libcluster, :topologies)[:local_epmd][:strategy] ||
        Application.get_env(:libcluster, :topologies)[:gossip_ex][:strategy]

    Logger.notice("Config: #{inspect(cache_opt ++ [cluster_type: cluster_type])}")

    # start Ets with a table name
    EtsDb.init(cache_opt[:ets_table])

    # MnUnSupervised.connect_mnesia_to_cluster(cache_opt.mn_table)

    # list to be supervised
    [
      # start libcluster
      {Cluster.Supervisor, [topologies, [name: CachingAnApi.ClusterSupervisor]]},

      # start Mnesia GenServer
      {MnDb.Supervisor, mn_opt},

      # start Cache GS
      {CacheGS.Supervisor, cache_opt}
    ]
    |> Supervisor.start_link(opts)
  end
end
