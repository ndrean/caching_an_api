import Config

# config :mnesia,
#   dir: 'mndb_#{node()}'

config :logger, :console, format: "[$date $time] $message\n", colors: [enabled: true]

config :caching_an_api,
  # env: config_env(),
  # :gossip or :k8
  cluster_type: :dns,
  # namespace: "stage",
  # :mn or :ets or nil
  store: :mn,
  mn_table: :mcache,
  ets_table: :ecache,
  # true or false
  disc_copy: true

import_config "#{Mix.env()}.exs"
