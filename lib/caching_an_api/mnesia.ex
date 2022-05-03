defmodule MnDb do
  alias :mnesia, as: Mnesia

  require Logger

  @moduledoc """
  This module is used by the Cache module and implements the setup of
  an MNesia store, the two functions `read` and `write`and manages the
  distribution of the Mnesia store within the connected nodes of a cluster.
  """
  @doc """
  Creates a schema _before_ starting Mnesia,
  then starts the Mnesia process, and finally creates a table.
  """

  # Mnesia alone
  def setup(_name) do
    inspect(node()) |> Logger.info()
  end

  def local_start(name) do
    with :ok <- ensure_schema_from_ram_to_disc_copy(:schema),
         :ok <- ensure_start(name),
         :ok <- ensure_table_create(name) do
      :ok
    end
  end

  def write(m_table, id, data) do
    Mnesia.transaction(fn ->
      Mnesia.write({m_table, id, data})
    end)
  end

  @doc """
  Reading the Mnesia store within a transaction for table "m_table" at the key "id".
  It returns `{:atom, value}`.

  ## Example

  ```bash
  iex> MnDb.read(:mcache, 1)
  ```
  """
  def read(m_table, id) do
    Mnesia.transaction(fn ->
      # use the lock?: :write to ensure no other node can modify

      case Mnesia.read({m_table, id}) do
        [] ->
          nil

        [{_m_table, _key, data}] ->
          data

        {_key, {:aborted, _cause}} ->
          :aborted
      end
    end)
  end

  ######################################
  @doc """
  This function returns a map of tables and their cookies.
  """
  def get_table_cookies(node \\ node()) do
    # tables
    :rpc.call(node, :mnesia, :system_info, [:tables])
    |> Enum.reduce(%{}, fn t, acc ->
      Map.put(acc, t, :rpc.call(node, :mnesia, :table_info, [t, :cookie]))
    end)
  end

  ########################################

  @doc """
  We declare fresh new nodes to Mnesia.
  This function must only be used to connect to newly started RAM nodes
  with an empty schema.
  If, for example, this function is used after the network has been partitioned,
  it can lead to inconsistent tables.
  """
  def update_mnesia_nodes do
    case Mnesia.change_config(:extra_db_nodes, Node.list()) do
      {:ok, [_ | _]} ->
        _nodes = Mnesia.system_info(:db_nodes)
        running_nodes = Mnesia.system_info(:running_db_nodes)
        Logger.info("Running nodes: #{inspect(running_nodes)}")
        :ok

      {:ok, []} ->
        Logger.info("Initialze Node List")
        # {:error, {:failed_to_connect_node}}
        :ok

      {:error, {:merge_schema_failed, msg}} ->
        Logger.info("merge_schema_failed")
        Logger.info("#{inspect(msg)}")
        ### TRIAL
        _node_db_folder = Application.get_env(:mnesia, :dir) |> to_string
        # {:ok, list} = File.rm_rf(node_db_folder)
        # inspect(list) |> Logger.info()
        # connect_mnesia_to_cluster(:mcache)
        ### TRIAL
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def connect_mnesia_to_cluster(name) do
    :ok = ensure_start(name)
    :ok = update_mnesia_nodes()
    :ok = ensure_schema_from_ram_to_disc_copy(:schema)
    :ok = ensure_table_create(name)
    :ok = ensure_table_copy_exists_at_node(name)

    tables = Mnesia.system_info(:local_tables)
    Logger.info("check tables: #{inspect(tables)}")

    Logger.info("Successfully connected Mnesia to the cluster!")
  end

  def ensure_schema_from_ram_to_disc_copy(name) do
    case Mnesia.change_table_copy_type(name, node(), :disc_copies) do
      {:atomic, :ok} ->
        Logger.info("#{name} created")
        :ok

      {:aborted, {:already_exists, :schema, _, _}} ->
        Logger.info("#{name} exists")
        :ok

      # {:error, {:already_exists, _name, _, :disc_copies}} ->
      #   Logger.info("table #{name} already on disc")
      #   :ok

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  def ensure_table_copy_exists_at_node(name) do
    with :ok <- wait_for(name) do
      case Mnesia.add_table_copy(name, node(), :disc_copies) do
        {:atomic, :ok} ->
          Logger.info("Table #{name} added to disc at node")
          :ok

        {:aborted, {:already_exists, _name, _node}} ->
          Logger.info("Table #{name} exists, already on disc at node")
          :ok

        {:error, {:already_exists, name, node, :disc_copies}} ->
          Logger.info("Table #{name} already on disc for #{node}")
          :ok
      end
    end
  end

  def ensure_table_create(name) do
    table = Mnesia.create_table(name, attributes: [:post_id, :data])

    with :ok <- wait_for(name) do
      case table do
        {:atomic, :ok} ->
          # with :ok <- wait_for(name) do
          Logger.info("Table #{name} created")
          :ok

        {:aborted, {:already_exists, name}} ->
          Logger.info("Table #{name} exists")
          :ok
      end
    end
  end

  def wait_for(name) do
    case Mnesia.wait_for_tables([name], 100) do
      :ok -> :ok
      {:timeout, _name} -> wait_for(name)
    end
  end

  def ensure_start(name) do
    Mnesia.start()

    case :mnesia.system_info(:is_running) do
      :yes ->
        Logger.info("Mnesia UP")
        :ok

      :no ->
        # local_start(name)
        # |> inspect(label: "local start")

        {:error, :mnesia_unexpectedly_stopped}

      :stopping ->
        {:error, :mnesia_unexpectedly_stopping}

      :starting ->
        Process.sleep(200)
        ensure_start(name)
    end
  end

  def ensure_schema_create(name) do
    case Mnesia.create_schema([node()]) do
      {:aborted, {:already_exists, ^name}} ->
        Logger.info("aborted local schema exists")
        :ok

      {:error, {_node, {:already_exists, __node}}} ->
        Logger.info("node local schema exists")
        :ok

      {:error, reason} ->
        {:error, reason}

      :ok ->
        :ok
    end
  end

  ##################################
  def delete_schema do
    Mnesia.delete_schema([node()])
  end

  def delete_schema_copy(name) do
    Mnesia.stop()
    ensure_delete_schema(name)
  end

  def ensure_delete_schema(name) do
    case :mnesia.system_info(:is_running) do
      :yes ->
        Mnesia.stop()
        Process.sleep(1000)
        ensure_delete_schema(name)

      :no ->
        with {:atomic, :ok} <- Mnesia.del_table_copy(name, node()) do
          :ok
        end

      :starting ->
        {:error, :mnesia_unexpectedly_starting}

      :stopping ->
        Process.sleep(1_000)
        ensure_delete_schema(name)
    end
  end
end
