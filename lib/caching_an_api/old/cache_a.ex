# defmodule CacheA do
#   use Agent
#   # require EtsDb
#   # require MnDb
#   require Logger

#   @doc """
#   We pass config options set in the Application level and name the GenServer pid with the module name.
#   """
#   def start_link(init_args) do
#     state = init_args[:state] || %{}
#     opt = Keyword.delete(init_args, :state)
#     Agent.start_link(fn -> {state, opt} end, name: __MODULE__)
#   end

#   # CacheA.start_link([store: :mn, table: :m, state: %{a: 1}])
#   def get(index) do
#     {state, opt} = Agent.get(__MODULE__, & &1)

#     case opt[:store] do
#       :mn ->
#         MnDb.read(index, opt[:mn_table])

#       :ets ->
#         EtsDb.get(index, opt[:ets_table])

#       :dcrdt ->
#         nil

#       nil ->
#         state[index]
#     end
#   end

#   def put(key, data) do
#     {state, opt} = Agent.get(__MODULE__, & &1)

#     case opt[:store] do
#       :ets ->
#         EtsDb.put(key, data, opt[:ets_table])

#       :mn ->
#         MnDb.write(key, data, opt[:mn_table])

#       :dcrt ->
#         nil

#       nil ->
#         new_state = Map.put(state, key, data)
#         :ok = Agent.cast(__MODULE__, fn {_state, opt} -> {new_state, opt} end)
#         new_state
#     end
#   end

#   def inverse(index, key) do
#   end

#   def inverse(index, key, _from, state) do
#     if state[:store] == :mn, do: MnDb.inverse(index, key, state[:mn_table])
#   end

#   def write(state, key, data) do
#   end

#   @doc """
#   Callback reacting to ERLANG MONITOR NODE `:nodedown` or `:nodeup` since we set `:net_kernel.monitor_nodes(true)` in the Cache module. Note that we also subscribed to Mnesia system event (with `:mnesia_down` or `:mnesia_up`). These are handled in the Mnesia module.
#   """

#   # def handle_info({:nodeup, _node}, state) do
#   #   # MnDb2.update_mnesia_nodes()
#   #   {:noreply, state}
#   # end

#   # def handle_info({:nodedown, _node}, state) do
#   #   # MnDb2.update_mnesia_nodes()
#   #   {:noreply, state}
#   # end
# end
