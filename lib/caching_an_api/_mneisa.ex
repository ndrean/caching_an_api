defmodule MnDbOld do
  alias :mnesia, as: Mnesia
  require Logger

  def write(m_table, key, data) do
    case Mnesia.transaction(fn ->
           Mnesia.write({m_table, key, data})
         end) do
      {:atomic, :ok} -> data
      {:aborted, reason} -> {:aborted, reason}
    end
  end

  def read(m_table, id) do
    case Mnesia.transaction(fn -> Mnesia.read({m_table, id}) end) do
      {:atomic, []} ->
        nil

      {:atomic, [{_m_table, _key, data}]} ->
        data

      {_key, {:aborted, cause}} ->
        {:aborted, cause}
    end
  end

  ########################################

  def connect_mnesia_to_cluster(name) do
    with :ok <- ensure_start(),
         :ok <- update_mnesia_nodes(),
         :ok <- ensure_table_from_ram_to_disc_copy(:schema),
         :ok <- ensure_table_create(name),
         :ok <- ensure_table_copy_exists_at_node(name) do
      {:ok, _name, _node} = activate_checkpoint(name)
    else
      {:error, reason} ->
        Logger.info("#{inspect(reason)}")
        {:error, reason}
    end
  end

  def ensure_start() do
    :ok = Mnesia.start()

    Mnesia.subscribe(:system)

    :ok
  end

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
        {:error, :merge_schema_failed}

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
