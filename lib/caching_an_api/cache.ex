defmodule Cache do
  require Logger

  @opts [
    store: Application.fetch_env!(:caching_an_api, :store) || :ets,
    mn_table: Application.fetch_env!(:caching_an_api, :mn_table) || :mcache,
    ets_table: Application.fetch_env!(:caching_an_api, :ets_table) || :ecache,
    disc_copy: Application.fetch_env!(:caching_an_api, :disc_copy) || false,
    cluster_type: Application.fetch_env!(:caching_an_api, :cluster_type) || :k8
  ]

  def read(index) do
    case @opts[:store] do
      :mn -> Mndb.read(index, @opts[:mn_table])
      :ets -> EtsDb.read(index, @opts[:ets_table])
    end
  end

  def write(index, data) do
    case @opts[:store] do
      :mn -> Mndb.write(index, data, @opts[:mn_table])
      :ets -> EtsDb.write(index, data, @opts[:ets_table])
    end
  end

  def inverse(index, key) do
    if @opts[:store] == :mn, do: Mndb.inverse(index, key, @opts[:mn_table])
  end
end
