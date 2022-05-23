# import Config

# config :mnesia,
#   dir: 'mndb_#{System.fetch_env!("POD_IP")}'

# config :caching_an_api,
#   # :gossip_cluster or :k8_cluster
#   cluster_type: :dns,
#   # namespace: "stage",
#   # :mn or :ets or nil
#   store: :mn,
#   mn_table: :mcache,
#   ets_table: :ecache,
#   # true or false
#   disc_copy: false
