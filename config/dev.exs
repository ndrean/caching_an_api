import Config

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
  ]
