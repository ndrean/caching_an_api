import Config

config :mnesia,
  dir: 'mndb_#{System.fetch_env!("POD_IP")}'

# dir: 'mndb_#{Node.self()}'
