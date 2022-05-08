defmodule MnDb do
  alias :mnesia, as: Mnesia
  use GenServer
  require Logger

  @moduledoc """
  This module wraps the Mnesia store and exposes two functions `read` and `write`. Furthermore, it manages the distribution of the Mnesia store within the connected nodes of a cluster.
  """

  @doc """
  This function is called by the supervisor and trigger the `MnDb.init` callback
  """
  def start_link(opts \\ [store: :mn, mn_table: :mcache]) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def read(key, name) do
    GenServer.call(__MODULE__, {:read, key, name})
  end

  def write(key, data, name) do
    GenServer.cast(__MODULE__, {:write, key, data, name})
  end

  ### Test functions
  def node_list(), do: GenServer.call(__MODULE__, {:node_list})
  def data_list(), do: GenServer.call(__MODULE__, {:data_list})
  def info(), do: :mnesia.system_info()
  #####################################################

  @doc """
  A flag is added to trigger the GenServer that runs the `terminate` callback when going down.
  """

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    name = opts[:mn_table]
    MnDb.connect_mnesia_to_cluster(name)

    {:ok, name}
  end

  #### TEST functions for rpc

  # GenServer.call({MnDb, :"b@127.0.0.1"}, :node_list)

  @impl true
  def handle_call({:data_list}, from, _state) do
    reply = :ets.tab2list(:mcache)
    # Logger.info("#{inspect(reply)}")
    {:reply, reply, from}
  end

  @impl true
  def handle_call(:node_list, from, state) do
    reply = Node.list()
    Logger.info("#{inspect(from)}")
    {:reply, reply, state}
  end

  #### END TEST functions

  @impl true
  def handle_call({:read, key, m_table}, _from, state) do
    reply =
      case Mnesia.transaction(fn -> Mnesia.read({m_table, key}) end) do
        {:atomic, []} ->
          nil

        {:atomic, [{_m_table, _key, data}]} ->
          data

        {:aborted, cause} ->
          {:aborted, cause}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_cast({:write, key, data, m_table}, state) do
    case Mnesia.transaction(fn ->
           Mnesia.write({m_table, key, data})
         end) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:aborted, reason}
    end

    {:noreply, state}
  end

  @doc """
  We update the Mnesia cluster based on it's system events to which we subscribe.
  """
  @impl true
  def handle_info({:mnesia_system_event, message}, state) do
    case message do
      {:mnesia_down, node} ->
        Logger.info("\u{2193}  #{node}", ansi_color: :magenta)

      {:mnesia_up, node} ->
        Logger.info("\u{2191} #{node}", ansi_color: :green)

      {:inconsistent_database, reason, node} ->
        Logger.critical("#{reason} at #{node}")
        # raise "partition"
        Mnesia.stop()
        send(__MODULE__, {:quit, {:shutdown, :network}})
        # {:stop, {:shutdown, :network}, state}
    end

    {:noreply, state}
  end

  def handle_info({:quit, {:shutdown, :network}}, from) do
    Logger.warn("GS terminating on network error ")
    # :ok = remove_old_node_table(node())
    {:stop, :shutdown, from}
  end

  def handle_info({:EXIT, _from, reason}, state) do
    Logger.warn("GenServer MnDb terminating at #{inspect(node())}")
    Mnesia.stop()
    {:stop, reason, state}
  end

  @doc """
  This will be triggered if we run `:init.stop()` for example.
  """
  @impl true
  def terminate(reason, state) do
    Logger.warn(" GenServer MnDb terminating: #{inspect(reason)}")
    System.cmd("say", ["bye to #{node() |> to_string() |> String.at(0)}"])

    {:ok, state}
  end

  # Node.disconnect(:"b@127.0.0.1")
  # Api.stream_synced(1..4)
  # :ets.tab2list(:mcache)
  ########################################

  @doc """
  Give that `name = :mcache` is the name of the table, we do:
  1. start Mnesia with `MnDb.ensure_start()`
  2. connect new node b@node to the `Node.list()` with `MnDb.update_mnesia_nodes()`
  3. we ensure that the schema table is of type `disc` to allow disc-resisdent tables on the node.
  4. To create the table and make a disc copy, you use `create_table` and specify the attributes of the table with `disc_copies: [node()]`
  5. b@node only has a copy of the schema at this point. To copy all the tables from a@node to b@node and maintain table types, you can run `add_table_copy`, or `MnDb.ensure_table_copy_exists_at_node(name)`.
  """

  def connect_mnesia_to_cluster(name) do
    Logger.info("Starting...")

    with {:start, :ok} <- {:start, ensure_start()},
         {:update_nodes, :ok} <- {:update_nodes, update_mnesia_nodes()},
         {:disc_schema, :ok} <-
           {:disc_schema, ensure_table_from_ram_to_disc_copy(:schema)},
         {:create_table, :ok} <- {:create_table, ensure_table_create(name)},
         {:ensure_table, :ok} <-
           {:ensure_table, ensure_table_copy_exists_at_node(name)} do
      :ok
    else
      {:start, {:error, reason}} -> {:error, :start, reason}
      {:update_nodes, {:error, reason}} -> {:error, :update_nodes, reason}
      {:disc_schema, {:error, reason}} -> {:error, :disc_schema, reason}
      {:create_table, {:error, reason}} -> {:error, :create_table, reason}
      {:ensure_table, {:error, reason}} -> {:error, :ensure_table, reason}
      {:error, reason} -> {:error, reason}
      {:aborted, reason} -> {:aborted, reason}
    end
  end

  def ensure_start() do
    case Mnesia.start() do
      :ok ->
        # Mnesia system event messaging
        Mnesia.subscribe(:system)
        :ok

      {:error, {:normal, {:mnesia_app, :start, [:normal, []]}}} ->
        Logger.debug("start loop")
        Process.sleep(1_000)
        ensure_start()
    end
  end

  @doc """
  We declare fresh new nodes to Mnesia. The doc says: "this function must only be used to connect to newly started RAM nodes with an empty schema. If, for example, this function is used after the network has been partitioned, it can lead to inconsistent tables".
  """
  def update_mnesia_nodes() do
    case Mnesia.change_config(:extra_db_nodes, Node.list()) do
      {:ok, [_ | _]} ->
        :ok

      {:ok, []} ->
        :ok

      {:error, reason} ->
        Logger.debug("U@N: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def remove_old_node_table(node) do
    {:ok, cwd} = File.cwd()
    path = cwd <> "/" <> "mndb_" <> to_string(node)
    {:ok, _} = File.rm_rf(path)
    Logger.info("RMRF")
    :ok
  end

  @doc """
  We ensure that the `:schema` table is of type `disc_copy` since otherwise, a `ram_copies`type schema doesn't any other disc-resident table.
  """
  def ensure_table_from_ram_to_disc_copy(name) do
    with :ok <- wait_for(name) do
      case Mnesia.change_table_copy_type(name, node(), :disc_copies) do
        {:atomic, :ok} ->
          :ok

        {:aborted, {:already_exists, _, _, _}} ->
          :ok

        {:aborted, reason} ->
          Logger.debug("ETR2D: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  def ensure_table_create(name) do
    table =
      Mnesia.create_table(
        name,
        access_mode: :read_write,
        attributes: [:post_id, :data],
        disc_copies: [node()],
        type: :ordered_set
      )

    case table do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, _name}} ->
        Logger.info("Table #{name} already present at #{node()}")
        :ok

      {:aborted, reason} ->
        Logger.debug("ETC: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  This one is needed to disc-copy the "remote" data table to the new node.
  """
  def ensure_table_copy_exists_at_node(name) do
    with :ok <- wait_for(name) do
      case Mnesia.add_table_copy(name, node(), :disc_copies) do
        {:atomic, :ok} ->
          :ok

        {:aborted, {:already_exists, _name, _node}} ->
          :ok

        {:error, {:already_exists, _table, _node, :disc_copies}} ->
          :ok

        {:aborted, reason} ->
          Logger.debug("ETCEAT: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, :ensure_table} ->
        ensure_table_copy_exists_at_node(name)
    end
  end

  def wait_for(name) do
    case Mnesia.wait_for_tables([name], 500) do
      :ok ->
        :ok

      {:ensure_table, :error} ->
        {:error, :ensure_table}

      {:timeout, _name} ->
        Logger.debug("loop wait #{name}")
        Process.sleep(200)
        wait_for(name)
    end
  end
end
