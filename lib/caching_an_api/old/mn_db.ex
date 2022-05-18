# defmodule MnDb do
#   alias :mnesia, as: Mnesia
#   use GenServer
#   require Logger
#   require IEx

#   @moduledoc """
#   This module wraps the Mnesia store and exposes two functions `read` and `write`. Furthermore, it manages the distribution of the Mnesia store within the connected nodes of a cluster.
#   """

#   def read(key, name) do
#     case Mnesia.transaction(fn -> Mnesia.read({name, key}) end) do
#       {:atomic, []} ->
#         nil

#       {:atomic, [{_m_table, _key, data}]} ->
#         data

#       {:aborted, cause} ->
#         {:aborted, cause}
#     end
#   end

#   def write(key, data, name) do
#     case Mnesia.transaction(fn -> Mnesia.write({name, key, data}) end) do
#       {:atomic, :ok} -> :ok
#       {:aborted, reason} -> {:aborted, reason}
#     end
#   end

#   def inverse(index, key, name) do
#     case Mnesia.transaction(fn ->
#            [{^name, ^index, data}] = Mnesia.read({name, index})
#            Mnesia.write({name, index, Map.put(data, key, true)})
#          end) do
#       {:atomic, :ok} ->
#         Mndb.read(index, name)

#       {:aborted, reason} ->
#         {:aborted, reason}
#     end
#   end

#   ### Test functions
#   def nodes(), do: GenServer.call(__MODULE__, {:nodes})
#   def data(), do: GenServer.call(__MODULE__, {:data})
#   def info(), do: :mnesia.system_info()

#   ### GenServer init client

#   @doc """
#   This function is called by the supervisor and trigger the `MnDb.init` callback
#   """
#   def start_link(opts \\ [store: :mn, mn_table: :mcache]) do
#     GenServer.start_link(__MODULE__, opts, name: __MODULE__)
#   end

#   ###

#   @doc """
#   A flag is added to trigger the GenServer that runs the `terminate` callback when going down.
#   """

#   @impl true
#   def init(opts) do
#     Process.flag(:trap_exit, true)

#     m_name = opts[:mn_table]
#     disc_copy = opts[:disc_copy]

#     if opts[:store] == :mn, do: MnDb.connect_mnesia_to_cluster(m_name, disc_copy)

#     state = Enum.into(opts, %{})
#     # if opts[:store] == :mn, do: m_name, else: opts[:ets_table]
#     {:ok, state}
#   end

#   #### TEST functions for rpc via GenServer.call

#   @doc """
#   TEST functions for rpc via GenServer.call
#   It can be executed from a remote node against another one.

#   ```elixir
#   GenServer.call({MnDb, :"b@127.0.0.1"}, {:node_list})
#   for node <- Node.list(), do: {node, GenServer.call({MnDb, node}, {:node_list}) }

#     ```
#   """
#   @impl true
#   def handle_call({:nodes}, _from, state) do
#     reply = Node.list()
#     {:reply, reply, state}
#   end

#   @impl true
#   def handle_call({:data}, _from, state) do
#     reply =
#       if state[:store] == :ets,
#         do: :ets.tab2list(state[:ets_table]),
#         else: :ets.tab2list(state[:mn_table])

#     {:reply, reply, state}
#   end

#   #### END TEST functions

#   # @impl true
#   # def handle_call({:read, key, m_table}, _from, state) do
#   #   reply =
#   #     case Mnesia.transaction(fn -> Mnesia.read({m_table, key}) end) do
#   #       {:atomic, []} ->
#   #         nil

#   #       {:atomic, [{_m_table, _key, data}]} ->
#   #         data

#   #       {:aborted, cause} ->
#   #         {:aborted, cause}
#   #     end

#   #   {:reply, reply, state}
#   # end

#   # @impl true
#   # def handle_cast({:write, key, data, m_table}, state) do
#   #   case Mnesia.transaction(fn ->
#   #          Mnesia.write({m_table, key, data})
#   #        end) do
#   #     {:atomic, :ok} -> :ok
#   #     {:aborted, reason} -> {:aborted, reason}
#   #   end

#   #   {:noreply, state}
#   # end

#   # @impl true
#   # def handle_call({:update, index, key, m_table}, _from, state) do
#   #   reply =
#   #     with :mn <- state.store do
#   #       case Mnesia.transaction(fn ->
#   #              [{^m_table, ^index, data}] = Mnesia.read({m_table, index})
#   #              Mnesia.write({m_table, index, Map.put(data, key, true)})
#   #            end) do
#   #         {:atomic, :ok} ->
#   #           {:ok, %{response: Mndb.read(index, m_table)}}

#   #         {:aborted, reason} ->
#   #           {:aborted, reason}
#   #       end
#   #     end

#   #   {:reply, reply, state}
#   # end

#   @doc """
#   We update the Mnesia cluster based on it's system events to which we subscribe.
#   """
#   @impl true
#   def handle_info({:mnesia_system_event, message}, state) do
#     case message do
#       {:mnesia_down, node} ->
#         update_mnesia_nodes()
#         Logger.info("\u{2193}  #{node}", ansi_color: :magenta)

#       {:mnesia_up, node} ->
#         # update_mnesia_nodes()
#         Logger.info("\u{2191} #{node}", ansi_color: :green)

#       {:inconsistent_database, reason, node} ->
#         Logger.warn("#{reason} at #{node}")
#         # raise "partition"
#         Mnesia.stop()
#         send(__MODULE__, {:quit, {:shutdown, :network}})
#         # {:stop, {:shutdown, :network}, state}
#     end

#     {:noreply, state}
#   end

#   def handle_info({:quit, {:shutdown, :network}}, from) do
#     Logger.warn("GS terminating on network error ")
#     {:stop, :shutdown, from}
#   end

#   def handle_info({:EXIT, _from, reason}, state) do
#     Logger.warn("GenServer MnDb terminating at #{inspect(node())}")
#     {:stop, reason, state}
#   end

#   @doc """
#   This will be triggered if we run `:init.stop()`.
#   """
#   @impl true
#   def terminate(reason, state) do
#     Logger.warn(" GenServer MnDb terminating: #{inspect(reason)}")
#     System.cmd("say", ["bye to #{node() |> to_string() |> String.at(0)}"])

#     {:ok, state}
#   end

#   # Node.disconnect(:"b@127.0.0.1")
#   # Api.stream_synced(1..4)
#   # :ets.tab2list(:mcache)
#   ########################################

#   @doc """
#   Give that `name = :mcache` is the name of the table, we do:
#   1. start Mnesia with `MnDb.ensure_start()`
#   2. connect new node b@node to the `Node.list()` with `MnDb.update_mnesia_nodes()`
#   3. we ensure that the schema table is of type `disc` to allow disc-resisdent tables on the node.
#   4. To create the table and make a disc copy, you use `create_table` and specify the attributes of the table with `disc_copies: [node()]`
#   5. b@node only has a copy of the schema at this point. To copy all the tables from a@node to b@node and maintain table types, you can run `add_table_copy`, or `MnDb.ensure_table_copy_exists_at_node(name)`.
#   """

#   def connect_mnesia_to_cluster(name, disc_copy? \\ false) do
#     Logger.info("Starting...")
#     # IEx.pry()

#     with {:start, :ok} <- {:start, ensure_start()},
#          {:update_nodes, :ok} <- {:update_nodes, update_mnesia_nodes()},
#          {:disc_schema, :ok} <-
#            {:disc_schema, ensure_schema_from_ram_to_disc_copy(disc_copy?)},
#          {:create_table, :ok} <- {:create_table, ensure_table_create(name, disc_copy?)},
#          {:ensure_table, :ok} <-
#            {:ensure_table, set_table_type_at_node(name, disc_copy?)} do
#       :ok
#     else
#       {:start, {:error, reason}} -> {:error, :start, reason}
#       {:update_nodes, {:error, reason}} -> {:error, :update_nodes, reason}
#       {:disc_schema, {:error, reason}} -> {:error, :disc_schema, reason}
#       {:create_table, {:error, reason}} -> {:error, :create_table, reason}
#       {:ensure_table, {:error, reason}} -> {:error, :ensure_table, reason}
#       {:error, reason} -> {:error, reason}
#       {:aborted, reason} -> {:aborted, reason}
#     end
#   end

#   def ensure_start() do
#     case Mnesia.start() do
#       :ok ->
#         # Mnesia system event messaging
#         Mnesia.subscribe(:system)
#         :ok

#       {:error, {:normal, {:mnesia_app, :start, [:normal, []]}}} ->
#         Logger.debug("start loop")
#         Process.sleep(1_000)
#         ensure_start()
#     end
#   end

#   @doc """
#   We declare fresh new nodes to Mnesia. The doc says: "this function must only be used to connect to newly started RAM nodes with an empty schema. If, for example, this function is used after the network has been partitioned, it can lead to inconsistent tables".
#   """
#   def update_mnesia_nodes() do
#     case Mnesia.change_config(:extra_db_nodes, Node.list()) do
#       {:ok, [_ | _]} ->
#         :ok

#       {:ok, []} ->
#         :ok

#       {:error, reason} ->
#         Logger.debug("U@N: #{inspect(reason)}")
#         {:error, reason}
#     end
#   end

#   @doc """
#   We ensure that the `:schema` table is of type `disc_copies` since a `ram_copies`type schema doesn't allow other disc-resident tables.
#   """
#   def ensure_schema_from_ram_to_disc_copy(disc_copy) do
#     with :disc_copy <- disc_copy,
#          :ok <- wait_for(:schema) do
#       case Mnesia.change_table_copy_type(:schema, node(), :disc_copies) do
#         {:atomic, :ok} ->
#           :ok

#         {:aborted, {:already_exists, _, _, _}} ->
#           :ok

#         {:aborted, reason} ->
#           Logger.debug("schema: #{inspect(reason)}")
#           {:error, reason}
#       end
#     else
#       _ -> :ok
#     end
#   end

#   def ensure_table_create(name, disc_copy) do
#     table =
#       case disc_copy do
#         :disc_copy ->
#           Mnesia.create_table(
#             name,
#             access_mode: :read_write,
#             attributes: [:post_id, :data],
#             disc_copies: [node()],
#             type: :ordered_set
#           )

#         _ ->
#           Mnesia.create_table(
#             name,
#             access_mode: :read_write,
#             attributes: [:post_id, :data],
#             type: :ordered_set
#           )
#       end

#     case table do
#       {:atomic, :ok} ->
#         :ok

#       {:aborted, {:already_exists, _name}} ->
#         Logger.info("Table #{name} already present at #{node()}")
#         :ok

#       {:aborted, reason} ->
#         Logger.debug("Ensure Table: #{inspect(reason)}")
#         {:error, reason}
#     end
#   end

#   @doc """
#   This one is needed to disc-copy the "remote" data table to the new node.
#   """
#   def set_table_type_at_node(name, type_copy) do
#     type = if type_copy != :disc_copy, do: :ram_copies, else: :disc_copies

#     with :ok <- wait_for(name) do
#       case Mnesia.add_table_copy(name, node(), type) do
#         {:atomic, :ok} ->
#           :ok

#         {:aborted, {:already_exists, _name, _node}} ->
#           :ok

#         {:error, {:already_exists, _table, _node, _}} ->
#           :ok

#         {:aborted, reason} ->
#           Logger.debug("set type at node: #{inspect(reason)}")
#           {:error, reason}
#       end
#     else
#       {:error, :ensure_table} ->
#         set_table_type_at_node(name, type_copy)
#     end
#   end

#   def wait_for(name) do
#     case Mnesia.wait_for_tables([name], 1000) do
#       :ok ->
#         :ok

#       {:ensure_table, :error} ->
#         {:error, :ensure_table}

#       {:timeout, _name} ->
#         Logger.debug("loop wait #{name}")
#         Process.sleep(500)
#         wait_for(name)
#     end
#   end

#   # defp remove_old_node_table(node) do
#   #   {:ok, cwd} = File.cwd()
#   #   path = cwd <> "/" <> "mndb_" <> to_string(node)
#   #   {:ok, _} = File.rm_rf(path)
#   #   Logger.info("RMRF")
#   #   :ok
#   # end
# end
