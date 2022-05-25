defmodule CachingAnApi.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    ####### get config in config.exs (store, libcluster) #########
    app_opt = [
      store: Application.fetch_env!(:caching_an_api, :store),
      mn_table: Application.fetch_env!(:caching_an_api, :mn_table) || :mcache,
      ets_table: Application.fetch_env!(:caching_an_api, :ets_table) || :ecache,
      # Application.fetch_env!(:caching_an_api, :disc_copy) || false,
      disc_copy: true,
      cluster_type: Application.fetch_env!(:caching_an_api, :cluster_type) || :gossip_cluster
    ]

    ### Init db #######
    EtsDb.init(app_opt)

    [
      {Cluster.Supervisor,
       [topology(app_opt[:cluster_type]), [name: CachingAnApi.ClusterSupervisor]]},
      {Mndb.Supervisor, app_opt}
    ]
    |> Supervisor.start_link(
      strategy: :one_for_one,
      name: CachingAnApi.Supervisor
    )
  end

  @doc """
  The library `libcluster` will perform a DNS query against a headless Kubernetes Service, getting the IP address of all Pods running our Erlang cluster.
  - Strategy.Kubernetes.DNS: This clustering strategy works by loading all your Erlang nodes (within Pods) in the current Kubernetes namespace. It will fetch the addresses of all pods under a shared headless service and attempt to connect. It will continually monitor and update its connections every 5s.
  - Strategy.Kubernetes, lookup mode: pods: your pod must be running as a service account with the ability to list pods. For mode: :ip, it uses `app_name@ip`. That is: it uses the IP address directly, e.g. myapp@10.42.1.49.

  """
  def topology(key) do
    case key do
      # your pod must be running as a "service account" with the ability to list pods.
      :k8 ->
        [
          k8: [
            strategy: Elixir.Cluster.Strategy.Kubernetes,
            config: [
              mode: :ip,
              kubernetes_ip_lookup_mode: :pods,
              polling_interval: 5_000,
              kubernetes_selector: "app=#{System.fetch_env!("APP_NAME")}",
              kubernetes_node_basename: System.fetch_env!("SERVICE_NAME"),
              kubernetes_namespace: System.fetch_env!("NAMESPACE")
            ]
          ]
        ]

      :gossip ->
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

      :dns ->
        [
          dns: [
            strategy: Elixir.Cluster.Strategy.Kubernetes.DNS,
            config: [
              # "myapp-svc-headless",
              service: System.fetch_env!("SERVICE_NAME"),
              # "stage",
              kubernetes_namespace: System.fetch_env!("NAMESPACE"),
              polling_interval: 5_000,
              # "myapp"
              application_name: System.fetch_env!("APP_NAME")
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

  defp get_ip, do: System.cmd("hostname", ["-s"]) |> elem(0) |> String.trim()
end
