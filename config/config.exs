import Config

config :mnesia,
  dir: 'mndb_#{Node.self()}'

config :logger, :console, format: "[$date $time] $message\n", colors: [enabled: true]

config :caching_an_api,
  cookie: :my_secret,
  store: :mn,
  mn_table: :mcache,
  ets_table: :ecache,
  disc_copy: nil,
  docker: true

# store: :mn or :ets or nil
# disc_copy: :discopy or false

### ----> use MIX_ENV=dev to get config :libcluster: gossip

### ----> use MIX_ENV=test to get config :libcluster: localEpmd

# libcluster will perform a DNS query against a headless Kubernetes Service, getting the IP address of all Pods running our Erlang cluster:
# k8: [
#   strategy: Cluster.Strategy.Kubernetes.DNS,
#   config: [
#     service: "my-elixir-app-svc-headless",
#     application_name: "caching_an_api"
#   ]
# ],

import_config "#{config_env()}.exs"
