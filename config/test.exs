import Config

config :libcluster,
  debug: false,
  topologies: [
    local_epmd: [
      strategy: Cluster.Strategy.LocalEpmd,
      config: [
        #   # ->  for strategy Cluster.Strategy.Epmd
        hosts: [:"a@127.0.0.1"]
      ],
      # use the default Erlang distribution protocol
      connect: {:net_kernel, :connect_node, []},
      # The function to use for disconnecting nodes. The node name will be appended to the argument list. Optional
      disconnect: {:erlang, :disconnect_node, []},
      # The function to use for listing nodes. This function must return a list of node names. Optional
      list_nodes: {:erlang, :nodes, [:connected]}
    ]
  ]
