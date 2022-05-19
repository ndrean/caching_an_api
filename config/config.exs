import Config

config :mnesia,
  dir: 'mndb_#{Node.self()}'

config :logger, :console, format: "[$date $time] $message\n", colors: [enabled: true]

config :caching_an_api,
  # env: config_env(),
  # :gossip or :k8 or :dns
  cluster_type: :k8,
  # namespace: "stage",
  # :mn or :ets or nil
  store: :mn,
  mn_table: :mcache,
  ets_table: :ecache,
  # true or false
  disc_copy: false

import_config "#{Mix.env()}.exs"
