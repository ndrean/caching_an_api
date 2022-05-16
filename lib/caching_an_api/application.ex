defmodule CachingAnApi.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    topologies = [
      # libcluster will perform a DNS query against a headless Kubernetes Service, getting the IP address of all Pods running our Erlang cluster:
      k8: [
        strategy: Cluster.Strategy.Kubernetes,
        config: [
          mode: :ip,
          kubernetes_namespace: "stage",
          polling_interval: 10_000,
          kubernetes_selector: "app=myapp",
          kubernetes_node_basename: "myapp",
          kubernetes_ip_lookup_mode: :pods
        ]
      ]
    ]

    # topologies = Application.get_env(:libcluster, :topologies) || []
    opts = [strategy: :one_for_one, name: CachingAnApi.Supervisor]

    cache_opt = [
      store: Application.get_env(:caching_an_api, :store) || :ets,
      mn_table: Application.get_env(:caching_an_api, :mn_table) || :mcache,
      ets_table: Application.get_env(:caching_an_api, :ets_table) || :ecache,
      disc_copy: Application.get_env(:caching_an_api, :disc_copy) || nil
    ]

    cluster_type =
      Application.get_env(:libcluster, :topologies)[:local_epmd][:strategy] ||
        Application.get_env(:libcluster, :topologies)[:gossip_ex][:strategy] ||
        Application.get_env(:libcluster, :topologies)[:k8][:strategy]

    Logger.notice("Config: #{inspect(cache_opt ++ [cluster_type: cluster_type])}")

    # Node.set_cookie(node(), :release_secret)
    Logger.debug("#{inspect(node())}, #{inspect(Node.get_cookie())}")
    # start Ets with a table name
    EtsDb.init(cache_opt)
    # MnDb2.connect_mnesia_to_cluster(cache_opt[:mn_table])

    # list to be supervised
    [
      # start libcluster
      {Cluster.Supervisor, [topologies, [name: CachingAnApi.ClusterSupervisor]]},

      # start Mnesia GenServer
      # {MnDb.Supervisor, cache_opt}

      # start Cache GS
      {CacheGS.Supervisor, cache_opt}
      # {CacheA, cache_opt ++ [state: %{}]} <- testing the Agent point of view
    ]
    |> Supervisor.start_link(opts)
  end

  # defp set_cluster_cookie() do
  #   require IEx

  #   cookie_to_atom = fn cookie ->
  #     if is_atom(cookie), do: cookie, else: String.to_atom(cookie)
  #   end

  #   cookie =
  #     (System.get_env("ERLANG_COOKIE") ||
  #        CachingAnApi.MixProject.project()
  #        |> get_in([:releases, :myapp, :cookie]))
  #     |> cookie_to_atom.()

  #   # IEx.pry()

  #   ("myapp" <> "@" <> System.get_env("POD_IP"))
  #   |> String.to_atom()
  #   |> Node.set_cookie(cookie)
  # end
end
