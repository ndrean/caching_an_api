import Config

config :mnesia,
  dir: 'mndb_#{Node.self()}',
  # cookie: "release_secret",
  env: config_env()

config :logger, :console, format: "[$date $time] $message\n", colors: [enabled: true]

config :caching_an_api,
  # :gossip_cluster or :k8_cluster
  cluster_type: :k8_cluster,
  # namespace: "stage",
  # :mn or :ets or nil
  store: :mn,
  mn_table: :mcache,
  ets_table: :ecache,
  # true or false
  disc_copy: true

import_config "#{Mix.env()}.exs"
