defmodule CachingAnApi.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # import Supervisor.Spec, warn: false

    topologies = [
      gossip: [
        strategy: Cluster.Strategy.Epmd,
        config: [
          #   # ->  for strategy Cluster.Strategy.Epmd
          hosts: [:a@MacBookND]
        ],
        connect: {:net_kernel, :connect_node, []},
        # The function to use for disconnecting nodes. The node
        # name will be appended to the argument list. Optional
        disconnect: {:erlang, :disconnect_node, []},
        # The function to use for listing nodes.
        # This function must return a list of node names. Optional
        list_nodes: {:erlang, :nodes, [:connected]}
      ]
    ]

    opts = [strategy: :one_for_one, name: CachingAnApi.Supervisor]

    # list to be supervised
    [
      # start the cache
      {CachingAnApi.Cache, [store: :mn, cache_on: true, mn_table: :mcache, ets_table: :ecache]},
      # start libcluster
      {Cluster.Supervisor, [topologies, [name: CachingAnApi.ClusterSupervisor]]}
    ]
    |> Supervisor.start_link(opts)
  end
end

# Cluster.CachingAnApiSupervisor
