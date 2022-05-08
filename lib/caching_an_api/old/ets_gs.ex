# defmodule EtsDb do
#   use GenServer
#   require Logger
#   alias :ets, as: Ets

#   @moduledoc """
#   This module contains the setup of an Ets table. It is used by the Cache module.
#   """

#   def start_link(opts) do
#     GenServer.start_link(__MODULE__, opts, name: __MODULE__)
#   end

#   def get(key) do
#     GenServer.call(__MODULE__, {:get, key})
#   end

#   def put(key, value) do
#     GenServer.cast(__MODULE__, {:put, key, value})
#   end

#   ###################################################

#   @doc """
#   The Ets store instanciation callback.
#   """
#   @impl true
#   def init(name) do
#     name =
#       Ets.new(
#         name,
#         [:ordered_set, :protected, :named_table, read_concurrency: true]
#       )

#     Logger.info("Ets cache up: #{name}")
#     {:ok, {name}}
#   end

#   @doc """
#   We used a callback since we put the table name in the state
#   """
#   @impl true
#   def handle_call({:get, key}, _from, {name}) do
#     return =
#       case Ets.lookup(name, key) do
#         [] -> nil
#         [{^key, data}] -> data
#         _ -> :error
#       end

#     {:reply, return, {name}}
#   end

#   @impl true
#   def handle_cast({:put, key, value}, {name}) do
#     # Ets.insert returns a boolean
#     case Ets.insert(name, {key, value}) do
#       true -> {:noreply, {name}}
#       false -> :error
#     end
#   end

#   @impl true
#   def handle_info(msg, name) do
#     Logger.info("#{inspect(msg)}")
#     {:noreply, name}
#   end
# end
