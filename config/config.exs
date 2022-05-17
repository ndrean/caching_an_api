import Config

config :mnesia,
  dir: 'mndb_#{Node.self()}',
  # cookie: "release_secret",
  env: config_env()

config :logger, :console, format: "[$date $time] $message\n", colors: [enabled: true]

# config :caching_an_api,
#   store: :mn,
#   mn_table: :mcache,
#   ets_table: :ecache,
#   disc_copy: nil

# store: :mn or :ets or nil
# disc_copy: true or false, nil

import_config "#{Mix.env()}.exs"
