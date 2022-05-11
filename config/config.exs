import Config

config :mnesia,
  dir: 'mndb_#{Node.self()}'

config :logger, :console, format: "[$date $time] $message\n", colors: [enabled: true]

config :caching_an_api,
  cookie: :my_secret,
  store: :mn,
  mn_table: :mcache,
  ets_table: :ecache,
  disc_copy: nil

# store: :mn or :ets or nil
# disc_copy: :discopy or false

config :libcluster,
  debug: false,
  topologies: [
    gossip_ex: [
      strategy: Elixir.Cluster.Strategy.Gossip,
      config: [
        port: 45892,
        if_addr: "0.0.0.0",
        multicast_addr: "255.255.255.255",
        broadcast_only: true
      ]
    ]
    # libcluster will perform a DNS query against a headless Kubernetes Service, getting the IP address of all Pods running our Erlang cluster:
    # k8: [
    #   strategy: Cluster.Strategy.Kubernetes.DNS,
    #   config: [
    #     service: "my-elixir-app-svc-headless",
    #     application_name: "caching_an_api"
    #   ]
    # ],
    # local_epmd: [
    #   strategy: Cluster.Strategy.Epmd,
    #   config: [
    #     #   # ->  for strategy Cluster.Strategy.Epmd
    #     hosts: [:"a@127.0.0.1"]
    #     # , :"b@127.0.0.1", :"c@127.0.0.1", :"d@127.0.0.1"]
    #   ]
    #   # use the default Erlang distribution protocol
    #   # connect: {:net_kernel, :connect_node, []},
    #   # The function to use for disconnecting nodes. The node
    #   # name will be appended to the argument list. Optional
    #   # disconnect: {:erlang, :disconnect_node, []},
    #   # The function to use for listing nodes.
    #   # This function must return a list of node names. Optional
    #   # list_nodes: {:erlang, :nodes, [:connected]}
    # ]
  ]

# import_config "#{config_env()}.exs"
