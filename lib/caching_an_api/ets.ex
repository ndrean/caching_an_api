defmodule EtsDb do
  use GenServer
  require Logger
  alias :ets, as: Ets

  @moduledoc """
  This module contains the setup of an Ets table. It is used by the Cache module.
  """

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  The Ets store is instanciated here.
  """

  def init(opts) do
    name =
      Ets.new(
        opts[:ets_table],
        [:ordered_set, :public, :named_table, read_concurrency: true, write_concurrency: true]
      )

    Logger.info("Ets cache up: #{name}")
    {:ok, %{ets_table: name}}
  end

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def put(key, value) do
    GenServer.cast(__MODULE__, {:put, key, value})
  end

  def handle_call({:get, key}, _from, %{ets_table: name} = state) do
    return =
      case Ets.lookup(name, key) do
        [] -> nil
        [{^key, data}] -> data
        _ -> :error
      end

    {:reply, return, state}
  end

  def handle_cast({:put, key, value}, %{ets_table: name} = state) do
    true = Ets.insert(name, {key, value})
    {:noreply, state}
  end
end
