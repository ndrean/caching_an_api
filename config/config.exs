import Config

config :mnesia,
  dir: 'mndb_#{Node.self()}'

# config :libcluster,
#   debug: true
