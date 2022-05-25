defmodule EtsDb do
  require Logger

  def init(opts) do
    name =
      :ets.new(
        opts[:ets_table],
        [:ordered_set, :public, :named_table, read_concurrency: true]
      )

    Logger.info("Ets cache up: #{name} at #{node()}", ansi_color: :cyan)
    :ok
  end

  def read(key, name) do
    case :ets.lookup(name, key) do
      [] -> nil
      [{^key, data}] -> data
      _ -> :error
    end
  end

  def write(key, data, name) do
    :ets.insert(name, {key, data})
    :ok
  end
end
