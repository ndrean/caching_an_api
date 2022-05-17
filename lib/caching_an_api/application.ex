defmodule CachingAnApi.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    opts = [strategy: :one_for_one, name: CachingAnApi.Supervisor]

    cache_opt = [
      store: Application.get_env(:caching_an_api, :store) || :ets,
      mn_table: Application.get_env(:caching_an_api, :mn_table) || :mcache,
      ets_table: Application.get_env(:caching_an_api, :ets_table) || :ecache,
      disc_copy: Application.get_env(:caching_an_api, :disc_copy) || nil
    ]

    ####### set me! #########
    cluster_type = :k8_cluster
    Logger.notice("Config: #{inspect(cache_opt ++ [cluster_type: cluster_type])}")
    Logger.debug("#{inspect(node())}, #{inspect(Node.get_cookie())}")

    ### Init Ets #######
    EtsDb.init(cache_opt)

    # list to be supervised
    [
      # start libcluster
      {Cluster.Supervisor, [topology(cluster_type), [name: CachingAnApi.ClusterSupervisor]]},
      # start Cache GS
      {CacheGS.Supervisor, cache_opt}
    ]
    |> Supervisor.start_link(opts)
  end

  @doc """
  `libcluster` will perform a DNS query against a headless Kubernetes Service, getting the IP address of all Pods running our Erlang cluster:
  """
  def topology(key) do
    case key do
      :k8_cluster ->
        [
          k8: [
            strategy: Cluster.Strategy.Kubernetes,
            config: [
              mode: :ip,
              kubernetes_ip_lookup_mode: :pods,
              polling_interval: 10_000,
              kubernetes_selector: "app=myapp",
              kubernetes_node_basename: "myapp",
              kubernetes_namespace: Application.get_env(:caching_an_api, :namespace)
            ]
          ]
        ]

      :gossip_cluster ->
        [
          gossip_ex: [
            strategy: Elixir.Cluster.Strategy.Gossip,
            config: [
              port: 45892,
              if_addr: "0.0.0.0",
              multicast_addr: "255.255.255.255",
              broadcast_only: true
            ]
          ]
        ]
    end
  end

  # only with Mix!
  # def release_name() do
  #   CachingAnApi.MixProject.project()[:releases]
  #   |> Keyword.keys()
  #   |> List.first()
  #   |> Atom.to_string()
  # end

  # defp check_ip, do: System.cmd("hostname", ["-s"]) |> elem(0) |> String.trim()
end
