defmodule EtsDb do
  require Logger

  def init(opts) do
    name =
      :ets.new(
        opts[:ets_table],
        [:ordered_set, :public, :named_table, read_concurrency: true]
      )

    Logger.info("Ets cache up: #{name}", ansi_color: :cyan)
    :ok
  end

  def get(key, name) do
    case :ets.lookup(name, key) do
      [] -> nil
      [{^key, data}] -> data
      _ -> :error
    end
  end

  def put(key, data, name) do
    :ets.insert(name, {key, data})
    :ok
  end
end
