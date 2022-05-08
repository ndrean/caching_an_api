defmodule EtsDb do
  require Logger

  def init(name) do
    name =
      :ets.new(
        name,
        [:ordered_set, :public, :named_table, read_concurrency: true]
      )

    Logger.info("Ets cache up: #{name}")
    :ok
  end

  def get(key, name \\ :ecache) do
    case :ets.lookup(name, key) do
      [] -> nil
      [{^key, data}] -> data
      _ -> :error
    end
  end

  def put(key, data, name \\ :ecache) do
    :ets.insert(name, {key, data})
    :ok
  end
end
