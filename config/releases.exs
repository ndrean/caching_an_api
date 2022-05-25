import Config

config :mnesia,
  dir: 'mndb_#{System.fetch_env!("POD_IP")}'

# dir: '/mn_db_#{System.cmd("hostname", ["-s"]) |> elem(0) |> String.trim()}'
