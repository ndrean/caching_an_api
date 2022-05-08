defmodule MnUnSupervised do
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

      {:aborted, cause} ->
        {:aborted, cause}
    end
  end

  def list(), do: :ets.tab2list(:mcache)
  ########################################

  def connect_mnesia_to_cluster(name) do
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
