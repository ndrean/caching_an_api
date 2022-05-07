defmodule MnDb do
  alias :mnesia, as: Mnesia
  use GenServer
  require Logger

  @moduledoc """
  This module wraps the Mnesia store and exposes two functions `read` and `write`. Furthermore, it manages the distribution of the Mnesia store within the connected nodes of a cluster.
  """

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def read(key) do
    GenServer.call(__MODULE__, {:read, key})
  end

  def write(key, data) do
    GenServer.cast(__MODULE__, {:write, key, data})
  end

  #####################################################
  @impl true
  def init(opts) do
    m_table = opts[:mn_table]
    Process.flag(:trap_exit, true)

    MnDb.connect_mnesia_to_cluster(m_table)

    {:ok, %{m_table: m_table}}
  end

  @impl true
  def handle_cast({:write, key, data}, %{m_table: m_table} = state) do
    case Mnesia.transaction(fn ->
           Mnesia.write({m_table, key, data})
         end) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:aborted, reason}
    end

    {:noreply, state}
  end

  @impl true
  def handle_call({:read, key}, _from, %{m_table: m_table} = state) do
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

  @doc """
  We update the knowledge o Mnesia system events.
  """
  @impl true
  def handle_info({:mnesia_system_event, message}, %{m_table: m_table} = state) do
    case message do
      {:mnesia_down, node} ->
        Logger.info("\u{2193}  #{node}")
        :ok = MnDb.update_mnesia_nodes()

      {:mnesia_up, node} ->
        Logger.info("\u{2191} #{node}")

      {:inconsistent_database, reason, node} ->
        Logger.critical("#{reason} at #{node}")
        :ok = connect_mnesia_to_cluster(m_table)
    end

    {:noreply, state}
  end

  def handle_info({:EXIT, _from, reason}, state) do
    Logger.warn("exiting Mnesia GS")
    {:stop, reason, state}
  end

  @doc """
  This will be triggered if we run `:init.stop()` for example.
  """
  @impl true
  def terminate(reason, _state) do
    Logger.critical(" GenServer MnDb terminating: #{inspect(reason)}")
    :ok = remove_old_node_table(node())
    :ok
  end

  ########################################

  @doc """
  Give that `name = :mcache` is the name of the table, we do:
  1. start Mnesia with `MnDb.ensure_start()`
  2. connect new node b@node to the `Node.list()` with `MnDb.update_mnesia_nodes()`
  3. we ensure that the schema table is of type `disc` to allow disc-resisdent tables on the node.
  4. To create the table and make a disc copy, you use `create_table` and specify the attributes of the table with `disc_copies: [node()]
  5. b@node only has a copy of the schema at this point. To copy all the tables from a@node to b@node and maintain table types, you can run `add_table_copy`, or `MnDb.ensure_table_copy_exists_at_node(name)`.
  """

  def connect_mnesia_to_cluster(name) do
    with {:start, :ok} <- {:start, :ok = ensure_start()},
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
    Logger.info("RMRF")
    {:ok, cwd} = File.cwd()
    path = cwd <> "/" <> "mndb_" <> to_string(node)
    {:ok, _} = File.rm_rf(path)
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

        {:error, {:already_exists, _table, _node, :disc_copies}} ->
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
        Logger.info("Table #{name} exists at #{node()}")
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
