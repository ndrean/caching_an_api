defmodule MnDb do
  alias :mnesia, as: Mnesia
  use GenServer
  require Logger

  @moduledoc """
  This module is used by the Cache module and implements the setup of
  an MNesia store, the two functions `read` and `write`and manages the
  distribution of the Mnesia store within the connected nodes of a cluster.
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

  def update_nodes do
    GenServer.cast(__MODULE__, {:update_nodes})
  end

  #####################################################
  @impl true
  def init(opts) do
    state = %{m_table: opts[:mn_table]}
    connect_mnesia_to_cluster(state.m_table)
    {:ok, state}
  end

  @impl true
  def handle_cast({:update_nodes}, state) do
    case update_mnesia_nodes() do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end

    {:noreply, state}
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

        {_key, {:aborted, cause}} ->
          {:aborted, cause}
      end

    {:reply, reply, state}
  end

  @doc """
  We clean the old data from the stopped node, and update the Mnesia cluster.
  Use MNESIA SYSTEM EVENT or ERLANG MONITOR NODES
  - first one we can react in this module with MNESIA ":mnesia_down" ,
  - with the 2d one, this is done in the Cache module with ERLANG ":nodedown".
  """
  @impl true
  def handle_info({:mnesia_system_event, message}, state) do
    Logger.info("#{inspect(message)}")

    with {:mnesia_down, node} <- message do
      MnDb.update_nodes()
      :ok = remove_old_node_table(node)
    end

    {:noreply, state}
  end

  ########################################

  @doc """
  Give that `name = :mcache` is the name of the table, we do:

  1. start Mnesia with `MnDb.ensure_start()`

  2. connect new node b@node to the `Node.list()` with `MnDb.update_mnesia_nodes()`

  3. To make new the new node b capable of storing disc copies, we need to change the schema table type on b from "ram_copies" to "disc_copies" with `change_table_copy_type`. We use `MnDb.ensure_table_from_ram_to_disc_copy(:schema)`

  4. To create the table and make a disc copy, you use `create_table` and specify the attributes of the table with `disc_copies: [node()]

  5. b@node only has a copy of the schema at this point. To copy all the tables from a@node to b@node and maintain table types, you can run `add_table_copy`, or `MnDb.ensure_table_copy_exists_at_node(name)`.
  """

  def connect_mnesia_to_cluster(name) do
    with :ok <- ensure_start(),
         :ok <- update_mnesia_nodes(),
         :ok <- ensure_table_from_ram_to_disc_copy(:schema),
         :ok <- ensure_table_create(name),
         :ok <- ensure_table_copy_exists_at_node(name) do
      :ok
    else
      {:error, reason} ->
        Logger.debug("#{inspect(reason)}")
        {:error, reason}
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

      {:error, {:merge_schema_failed, _msg}} ->
        Logger.debug("merge_schema_failed")
        # Logger.info("#{inspect(msg)}")
        {:error, :merge_schema_failed}

      {:error, reason} ->
        Logger.debug("reason")
        {:error, reason}
    end
  end

  @doc """
  Erase the folder storing the db of a node
  """
  def remove_old_node_table(node) do
    {:ok, cwd} = File.cwd()
    path = cwd <> "/" <> "mndb_" <> to_string(node)
    {:ok, _} = File.rm_rf(path)
    :ok
  end

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
          Logger.debug("#{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  def ensure_table_create(name) do
    table = Mnesia.create_table(name, attributes: [:post_id, :data], disc_copies: [node()])

    case table do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, _name}} ->
        :ok

      {:aborted, reason} ->
        Logger.debug("#{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  This one is needed to disc-copy the "remote" data table to the new node.
  """
  def ensure_table_copy_exists_at_node(name) do
    case Mnesia.add_table_copy(name, node(), :disc_copies) do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, _name, _node}} ->
        :ok

      {:error, {:already_exists, _table, _node, :disc_copies}} ->
        :ok

      {:aborted, reason} ->
        Logger.debug("#{inspect(reason)}")
        {:error, reason}

      {:error, reason} ->
        Logger.debug("#{inspect(reason)}")
    end
  end

  def wait_for(name) do
    case Mnesia.wait_for_tables([name], 100) do
      :ok ->
        :ok

      {:timeout, _name} ->
        Logger.debug("loop wait #{name}")
        wait_for(name)
    end
  end
end
