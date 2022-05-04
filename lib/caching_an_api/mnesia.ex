defmodule MnDb do
  alias :mnesia, as: Mnesia

  require Logger

  @moduledoc """
  This module is used by the Cache module and implements the setup of
  an MNesia store, the two functions `read` and `write`and manages the
  distribution of the Mnesia store within the connected nodes of a cluster.
  """

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
    # Logger.info("Start setup")

    with :ok <- ensure_start(),
         :ok <- update_mnesia_nodes(),
         :ok <- ensure_table_from_ram_to_disc_copy(:schema),
         :ok <- ensure_table_create(name),
         :ok <- ensure_table_copy_exists_at_node(name) do
      {:ok, _name, _node} = activate_checkpoint(name)
      # node_db_folder = Application.get_env(:mnesia, :dir) |> to_string
      # Logger.info("A local copy of the data exists at: #{node_db_folder}")
      # Logger.info("Successfully connected Mnesia to the cluster!")
    end
  end

  def ensure_start() do
    :ok = Mnesia.start()

    Mnesia.subscribe(:system)

    :ok
  end

  @doc """
  We declare fresh new nodes to Mnesia. This function must only be used to connect to newly started RAM nodes with an empty schema. If, for example, this function is used after the network has been partitioned, it can lead to inconsistent tables.
  """
  def update_mnesia_nodes() do
    case Mnesia.change_config(:extra_db_nodes, Node.list()) do
      {:ok, [_ | _]} ->
        running_nodes = Mnesia.system_info(:running_db_nodes)
        Logger.info("Running nodes: #{inspect(running_nodes)}")
        :ok

      {:ok, []} ->
        # Logger.info("Initialze Node List")
        :ok

      {:error, {:merge_schema_failed, _msg}} ->
        Logger.info("merge_schema_failed")
        # Logger.info("#{inspect(msg)}")
        :error

      {:error, reason} ->
        {:error, reason}
    end
  end

  def ensure_table_from_ram_to_disc_copy(name) do
    with :ok <- wait_for(name) do
      case Mnesia.change_table_copy_type(name, node(), :disc_copies) do
        {:atomic, :ok} ->
          # Logger.info("#{name} created")
          :ok

        {:aborted, {:already_exists, _, _, _}} ->
          # Logger.info("#{name} already exists on disc")
          :ok

        {:error, {:already_exists, _table, _node, :disc_copies}} ->
          # Logger.info("error #{name} already")
          :ok

        {:aborted, reason} ->
          {:error, reason}
      end
    end
  end

  def ensure_table_create(name) do
    table = Mnesia.create_table(name, attributes: [:post_id, :data], disc_copies: [node()])

    case table do
      {:atomic, :ok} ->
        # Logger.info("Table #{name} created")
        :ok

      {:aborted, {:already_exists, _name}} ->
        # Logger.info("Table #{name} exists")
        :ok

      {:aborted, reason} ->
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
          # Logger.info("Remote table #{name} added to disc at node")
          :ok

        {:aborted, {:already_exists, _name, _node}} ->
          # Logger.info("Table #{name} already on disc at node")
          :ok

        {:error, {:already_exists, _table, _node, :disc_copies}} ->
          # Logger.info("error #{name} already")
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

  def activate_checkpoint(name) do
    {:ok, _name, _node} = Mnesia.activate_checkpoint(max: [name])
  end

  ##################################
  # def delete_schema do
  #   Mnesia.delete_schema([node()])
  # end

  # def delete_schema_copy(name) do
  #   Mnesia.stop()
  #   ensure_delete_schema(name)
  # end

  # def ensure_delete_schema(name) do
  #   case :mnesia.system_info(:is_running) do
  #     :yes ->
  #       Mnesia.stop()
  #       Process.sleep(1000)
  #       ensure_delete_schema(name)

  #     :no ->
  #       with {:atomic, :ok} <- Mnesia.del_table_copy(name, node()) do
  #         :ok
  #       end

  #     :starting ->
  #       {:error, :mnesia_unexpectedly_starting}

  #     :stopping ->
  #       Process.sleep(1_000)
  #       ensure_delete_schema(name)
  #   end
  # end

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
end
