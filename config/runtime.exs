import Config

config :caching_an_api,
  namespace: "stage",
  store: :mn,
  mn_table: :mcache,
  ets_table: :ecache,
  disc_copy: nil
