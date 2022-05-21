# defmodule CacheGS do
#   use GenServer
#   # require EtsDb
#   # require MnDb
#   require Logger

#   @doc """
#   We pass config options set in the Application level and name the GenServer pid with the module name.
#   """
#   def start_link(opts) do
#     GenServer.start_link(__MODULE__, opts, name: __MODULE__)
#     # debug: [:statistics, :trace]
#   end

#   @doc """
#   Sync call
#   """
#   def read(key) do
#     GenServer.call(__MODULE__, {:get, key})
#   end

#   @doc """
#   Cast is an Async update since we don't inform the client
#   """
#   def write(key, data) do
#     GenServer.cast(__MODULE__, {:put, key, data})
#   end

#   def inverse(index, key) do
#     GenServer.call(__MODULE__, {:inverse, index, key})
#   end

#   ###########################################
#   ## callbacks

#   @doc """
#   `GenServer.start_link` calls `GenServer.init` and passes the arguments "opts"
#   that where set in "Application.ex".
#   Note: the argument in `init` should match the 2d argument used in `GenServer.start_link`.

#   The GenServer process subscribes to node status change messages (:nodeup, :nodedown)

#   """
#   @impl true
#   def init(opts) do
#     # subscribe to node changes
#     :ok = :net_kernel.monitor_nodes(true)
#     Process.flag(:trap_exit, true)
#     Process.whereis(CacheGS) |> Cluster.Events.subscribe()
#     state = opts

#     case opts[:store] do
#       nil ->
#         state = Enum.into(opts, %{}) |> Map.put(:req, %{})
#         {:ok, state}

#       _ ->
#         {:ok, state}
#     end
#   end

#   @impl true
#   def handle_call({:inverse, index, key}, _from, state) do
#     reply = if state[:store] == :mn, do: Mndb.inverse(index, key, state[:mn_table])

#     {:reply, reply, state}
#   end

#   @impl true
#   def handle_call({:get, key}, _from, state) do
#     cache =
#       case state[:store] do
#         :mn ->
#           Mndb.read(key, state[:mn_table])

#         :ets ->
#           EtsDb.read(key, state[:ets_table])

#         nil ->
#           state.req[key]
#       end

#     {:reply, cache, state}
#   end

#   @impl true
#   def handle_cast({:put, key, data}, state) do
#     new_state =
#       case state[:store] do
#         :ets ->
#           EtsDb.write(key, data, state[:ets_table])
#           state

#         :mn ->
#           Mndb.write(key, data, state[:mn_table])
#           state

#         nil ->
#           %{state | req: Map.put(state.req, key, data)}
#       end

#     {:noreply, new_state}
#   end

#   @doc """
#   Callback reacting to ERLANG MONITOR NODE `:nodedown` or `:nodeup` since we set `:net_kernel.monitor_nodes(true)` in the Cache module. Note that we also subscribed to Mnesia system event (with `:mnesia_down` or `:mnesia_up`). These are handled in the Mnesia module.
#   """
#   @impl true
#   def handle_info({:nodeup, _node}, state) do
#     Logger.debug("#{inspect(node())} is UP!")
#     :ok = Mndb.update()
#     :ok = Mndb.connect(state[:mn_table], state[:disc_copy])
#     {:noreply, state}
#   end

#   @impl true
#   def handle_info({:nodedown, _node}, state) do
#     Mndb.update()
#     {:noreply, state}
#   end

#   @impl true
#   def handle_info({:mnesia_system_event, message}, state) do
#     Logger.info("#{inspect(message)}")

#     with {:inconsistent_database, reason, _node} <- message do
#       # Logger.critical("#{reason} at #{node}")
#       Logger.warn("Error: #{inspect(reason)} ")
#       send(__MODULE__, {:quit, {:shutdown, :network}})
#     end

#     {:noreply, state}
#   end

#   @impl true
#   def handle_info({:quit, {:shutdown, :network}}, state) do
#     # System.cmd("say", ["bye to #{node() |> to_string() |> String.at(0)}"])
#     :mnesia.stop()
#     {:stop, state}
#   end

#   @impl true
#   def terminate(_, _state) do
#     :mnesia.stop()
#     Logger.warn("GS stopped")
#   end
# end
