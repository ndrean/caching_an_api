# defmodule Mndb2 do
#   alias :mnesia, as: Mnesia
#   require Logger
#   use GenServer

#   @moduledoc """
#   This module wraps the Mnesia store and exposes two functions `read` and `write`. Furthermore, it manages the distribution of the Mnesia store within the connected nodes of a cluster.
#   """

#   def read(key, m_table) do
#     case Mnesia.transaction(fn -> Mnesia.read({m_table, key}) end) do
#       {:atomic, []} -> nil
#       {:atomic, [{_m_table, _key, data}]} -> data
#       {:aborted, cause} -> {:aborted, cause}
#     end
#   end

#   def write(key, data, m_table) do
#     case Mnesia.transaction(fn ->
#            Mnesia.write({m_table, key, data})
#          end) do
#       {:atomic, :ok} -> :ok
#       {:aborted, reason} -> {:aborted, reason}
#     end
#   end

#   def inverse(index, key, m_table) do
#     case Mnesia.transaction(fn ->
#            [{^m_table, ^index, data}] = Mnesia.read({m_table, index})
#            Mnesia.write({m_table, index, Map.put(data, key, true)})
#          end) do
#       {:atomic, :ok} -> Mndb.read(index, m_table)
#       {:aborted, reason} -> {:aborted, reason}
#     end
#   end

#   ##### Usefull functions

#   def info(), do: :mnesia.system_info()

#   @doc """
#   A test function for rpc execution on another node via `GenServer.call`. Instead of `:rpc.call(<node>, Module, :function, [args])`, you do `GenSever.call({Module, <node>},{:function})`.

#   ```elixir
#   GenServer.call({Mndb, :"b@127.0.0.1"}, {:data})
#   for node <- Node.list(), do: {node, GenServer.call({Mndb, node}, {:data}) }
#     ```
#   """
#   def data(), do: GenServer.call(__MODULE__, {:data})

#   def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

#   ################ Server callbacks
#   @doc """
#   Flag to trap exit, Erlang monitor ndoes, Mnesia init (schema, start, subscribe). A flag is added to trigger the GenServer that runs the `terminate` callback when going down.
#   """
#   @impl true
#   def init(opts) do
#     # %{store: store, mn_table: mn_table} =
#     state = Enum.into(opts, %{})

#     Process.flag(:trap_exit, true)

#     with :ok <- :net_kernel.monitor_nodes(true),
#          :ok <- ensure_start() do
#       {:ok, state}
#     else
#       {:error, reason} -> {:error, reason}
#     end
#   end

#   ############ Mnesia functions
#   def ensure_start() do
#     :stopped = Mnesia.stop()
#     # with :ok <- ensure_stop(),
#     # Logger.debug("Start node: #{inspect(node())}, #{inspect(Node.list())}")

#     if(Node.list() == [], do: Mnesia.create_schema([node()]))
#     # with [] <- Node.list() do
#     #   :ok =
#     #     case Mnesia.create_schema([node()]) do
#     #       :ok ->
#     #         Logger.debug("Ensure start: Schema created at #{inspect(node())}")
#     #         :ok

#     #       {:error, {node, {:already_exists, nodes}}} ->
#     #         Logger.debug(
#     #           "Ensure start: Schema already exists at #{inspect(node)} and #{inspect(nodes)}"
#     #         )

#     #         :ok
#     #     end
#     # else
#     #   _ ->
#     #     Logger.debug("Ensure start: no schema created")
#     #     :ok
#     # end

#     with :ok <- Mnesia.start(),
#          {:ok, _node} <- Mnesia.subscribe(:system) do
#       Logger.debug(
#         "Start node: #{inspect(node())}, Mnesia started & subscribed: #{inspect(Mndb.info())}"
#       )

#       Process.sleep(500)
#       :ok
#     end
#   end

#   @doc """
#   - Erlang EPMD send a `:nodeup` event. We update Mnesia knowledge and instanciate the table.
#   - We use the Mnesia UP event to update the Mnesia cluster. Then if we want disc copies, we have to "create" the disc in the node by copying the schema onto the node's disc. Then we can disc-copy the table. If no disc-copy of the schema, only a RAM copy will exist.
#   - We capture all Mnesia system events. In case of a network failure, we have an inconsistant database and shut down Mnesia until a new connection appears with EPMD.

#   """
#   @impl true
#   def handle_info({:nodeup, node}, state) do
#     Logger.debug("Node #{inspect(node)} is UP, with: #{inspect(node)}")
#     # current_node = node()
#     # discovered_node = node

#     :ok = Mndb.create_table(state.mn_table, state.disc_copy)
#     # Logger.debug("handle-up-after-connect: #{inspect(Mndb.info())}")
#     # Process.sleep(500)
#     :ok = Mndb.update()
#     # Logger.debug("handle-up-thne-after update: #{inspect(Mndb.info())}")
#     # Process.sleep(500)
#     {:noreply, state}
#   end

#   @impl true
#   def handle_info({:nodedown, _node}, state) do
#     Mndb.update()
#     {:noreply, state}
#   end

#   @impl true
#   def handle_info(
#         {:mnesia_system_event, {:mnesia_up, node}},
#         state
#       ) do
#     # Mndb.update()
#     Logger.debug("Mnesia UP: new: #{inspect(node)}, current: #{inspect(node())}")
#     :ok = Mndb.copy_schema()
#     :ok = Mndb.remote_to_node(state.mn_table, state.disc_copy)
#     Logger.debug("handle-up-thne-after update: #{inspect(Mndb.info())}")
#     Process.sleep(500)

#     {:noreply, state}
#   end

#   @impl true
#   def handle_info({:mnesia_system_event, message}, state) do
#     Logger.info("#{inspect(message)}")

#     with {:inconsistent_database, reason, _node} <- message do
#       Logger.warn("Error: #{inspect(reason)} ")
#       send(__MODULE__, {:stop, {:shutdown, :network}})
#     end

#     {:noreply, state}
#   end

#   @impl true
#   def terminate(_, state) do
#     Mnesia.stop()
#     Logger.warn("GS Terminated")
#     {:kill, state}
#   end

#   ############### Mnesia functions ##########################
#   def connect(name, disc_copy? \\ false) do
#     Logger.debug("Starting connect.......#{inspect(node())}")

#     # with {:disc_schema, :ok} <- {:disc_schema, Mndb.copy_schema()},
#     with {:create_table, :ok} <- {:create_table, Mndb.create_table(name, disc_copy?)},
#          {:remote_to_node, :ok} <- {:remote_to_node, Mndb.remote_to_node(name, disc_copy?)} do
#       :ok
#     else
#       # {:disc_schema, {:error, reason}} -> {:error, {:disc_schema, reason}}
#       {:create_table, {:error, reason}} ->
#         {:error, {:create_table, reason}}

#       {:remote_to_node, {:error, reason}} ->
#         {:error, {:remote_to_node, reason}}

#       {:error, reason} ->
#         {:error, reason}
#         # {:aborted, reason} -> {:aborted, reason}
#     end
#   end

#   @doc """
#   We declare fresh new nodes to Mnesia. The doc says: "this function must only be used to connect to newly started RAM nodes with an empty schema. If, for example, this function is used after the network has been partitioned, it can lead to inconsistent tables".
#   """
#   def update() do
#     Logger.debug("Update inspect init: #{inspect(node())}, #{inspect(Node.list())}")

#     case Mnesia.change_config(:extra_db_nodes, Node.list()) do
#       {:ok, [t | h]} ->
#         Logger.debug("Update #{inspect(node())}- chg conf: #{inspect(t)}, #{inspect(h)}")
#         :ok

#       {:ok, []} ->
#         Logger.debug("Update #{inspect(node())} - cong config: []")
#         :ok

#       {:error, reason} ->
#         Logger.debug("U@N: #{inspect(node())} - #{inspect(reason)}")
#         {:error, reason}
#     end
#   end

#   @doc """
#   We ensure that the `:schema` table is of type `disc_copies` since a `ram_copies`type schema doesn't allow other disc-resident tables.
#   """

#   def copy_schema() do
#     Logger.debug("Copy schema for: #{inspect(node())}")

#     # case disc_copy do
#     # true ->
#     Mnesia.wait_for_tables([:schema], 1_000)

#     case Mnesia.change_table_copy_type(:schema, node(), :disc_copies) do
#       #
#       {:atomic, :ok} ->
#         Logger.debug("Schema of disc copy type #{inspect(node())}")
#         :ok

#       #
#       {:aborted, {:already_exists, :schema, _, _}} ->
#         Logger.debug("Schema already of disc copy type #{inspect(node())}")
#         :ok

#       #
#       {:aborted, reason} ->
#         Logger.debug("schema: #{inspect(reason)}")
#         {:error, reason}
#     end

#     # false ->
#     # :ok
#     # end
#   end

#   def create_table(name, disc_copy) do
#     table =
#       case disc_copy do
#         true ->
#           Mnesia.create_table(name,
#             access_mode: :read_write,
#             attributes: [:post_id, :data],
#             disc_copies: [node()],
#             type: :ordered_set
#           )

#         false ->
#           Mnesia.create_table(:mcache,
#             access_mode: :read_write,
#             attributes: [:post_id, :data],
#             type: :ordered_set
#           )
#       end

#     :ok = Mnesia.wait_for_tables([name], 3_000)

#     case table do
#       {:atomic, :ok} ->
#         Logger.debug("#{inspect(name)} created #{inspect(node())}")
#         :ok

#       {:aborted, {:already_exists, _name}} ->
#         Logger.debug("#{inspect(name)} already exists #{inspect(node())}")
#         :ok

#       {:aborted, reason} ->
#         Logger.debug("Ensure Table: #{inspect(reason)}, #{inspect(node())}")
#         {:error, reason}
#     end
#   end

#   @doc """
#   This one is needed to disc-copy the "remote" data table to the new node.
#   """
#   def remote_to_node(name, disc_copy) do
#     type = unless disc_copy, do: :ram_copies, else: :disc_copies
#     Logger.debug("#{inspect(node())}: in remote: #{inspect(type)}")

#     with :ok <- Mnesia.wait_for_tables([name], 3_000) do
#       case Mnesia.add_table_copy(name, node(), type) do
#         {:atomic, :ok} ->
#           Logger.debug("Table copied #{inspect(node())}")
#           # Logger.debug("Remote: #{inspect(node())},  #{inspect(Mndb.info())}}")
#           Process.sleep(500)
#           :ok

#         {:aborted, {:already_exists, _name, _node}} ->
#           Logger.debug("Table already copied, from Aborted, #{inspect(node())}")
#           # Logger.debug("Remote: #{inspect(node())},  #{inspect(Mndb.info())}}")
#           Process.sleep(500)
#           :ok

#         {:error, {:already_exists, _table, _node, _}} ->
#           Logger.debug("Table already copied, from Error, #{inspect(node())}")
#           # Logger.debug("Remote: #{inspect(node())},  #{inspect(Mndb.info())}}")
#           Process.sleep(500)
#           :ok

#         {:aborted, reason} ->
#           Logger.debug("set type at node: #{inspect(reason)}, #{inspect(node())}")
#           {:error, reason}
#       end
#     else
#       # Logger.debug(
#       #     "Error remote copy #{inspect(name)}: #{inspect(reason)}, #{inspect(node())}"
#       #   )
#       {:error, reason} -> {:error, reason}
#     end

#     :ok
#   end

#   @impl true
#   def handle_call({:data}, _from, %{mn_table: m_table} = state) do
#     reply = unless :ets.whereis(:mcache) == :undefined, do: :ets.tab2list(m_table)
#     {:reply, reply, state}
#   end

#   # def ensure_stop() do
#   #   case Mnesia.stop() do
#   #     :stopped -> :ok
#   #     _ -> check_stop()
#   #   end
#   # end

#   # def check_stop() do
#   #   case Mnesia.system_info(:is_running) do
#   #     :no ->
#   #       :ok

#   #     :stopping ->
#   #       Process.sleep(1_000)
#   #       check_stop()

#   #     _ ->
#   #       {:error, :mnesia_not_stopping}
#   #   end
#   # end
# end