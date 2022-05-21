defmodule Mndb do
  alias :mnesia, as: Mnesia
  require Logger
  use GenServer

  @moduledoc """
  This module wraps the Mnesia store and exposes two functions `read` and `write`. Furthermore, it manages the distribution of the Mnesia store within the connected nodes of a cluster.
  """

  def read(key, m_table) do
    case Mnesia.transaction(fn -> Mnesia.read({m_table, key}) end) do
      {:atomic, []} -> nil
      {:atomic, [{_m_table, _key, data}]} -> data
      {:aborted, cause} -> {:aborted, cause}
    end
  end

  def write(key, data, m_table) do
    case Mnesia.transaction(fn ->
           Mnesia.write({m_table, key, data})
         end) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:aborted, reason}
    end
  end

  def inverse(index, key, m_table) do
    case Mnesia.transaction(fn ->
           [{^m_table, ^index, data}] = Mnesia.read({m_table, index})
           Mnesia.write({m_table, index, Map.put(data, key, true)})
         end) do
      {:atomic, :ok} -> Mndb.read(index, m_table)
      {:aborted, reason} -> {:aborted, reason}
    end
  end

  ##### Usefull functions

  def info(), do: :mnesia.system_info()

  @doc """
  A test function for rpc execution on another node via `GenServer.call`. Instead of `:rpc.call(<node>, Module, :function, [args])`, you do `GenSever.call({Module, <node>},{:function})`.

  ```elixir
  GenServer.call({Mndb, :"b@127.0.0.1"}, {:data})
  for node <- Node.list(), do: {node, GenServer.call({Mndb, node}, {:data}) }
    ```
  """
  def data(), do: GenServer.call(__MODULE__, {:data})

  ############ Mnesia functions
  def ensure_start() do
    :ok =
      with :ok <- ensure_stop(),
           [] <- Node.list() do
        case Mnesia.create_schema([node()]) do
          :ok ->
            # Logger.debug("Schema created at #{inspect(node())}")
            :ok

          {:error, {_node, {:already_exists, _nodes}}} ->
            # Logger.debug("Schema already exists at #{inspect(node)} and #{inspect(nodes)}")
            :ok
        end
      else
        _ ->
          :ok
      end

    case Mnesia.start() do
      :ok ->
        Mnesia.subscribe(:system)
        :ok

      {:error, reason} ->
        {:error, reason}

      {:shutdown, _} ->
        {:error, :start_failed}
    end
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  ################ Server callbacks
  @doc """
  Flag to trap exit, Erlang monitor ndoes, Mnesia init (schema, start, subscribe). A flag is added to trigger the GenServer that runs the `terminate` callback when going down.
  """
  @impl true
  def init(opts) do
    # %{store: store, mn_table: mn_table} =
    state = Enum.into(opts, %{})

    Process.flag(:trap_exit, true)
    :ok = :net_kernel.monitor_nodes(true)
    :ok = ensure_start()

    {:ok, state}
  end

  @doc """
  - Erlang EPMD send a `:nodeup` event. We update Mnesia knowledge and instanciate the table.
  - We use the Mnesia UP event to update the Mnesia cluster. Then if we want disc copies, we have to "create" the disc in the node by copying the schema onto the node's disc. Then we can disc-copy the table. If no disc-copy of the schema, only a RAM copy will exist.
  - We capture all Mnesia system events. In case of a network failure, we have an inconsistant database and shut down Mnesia until a new connection appears with EPMD.

  """
  @impl true
  def handle_info({:nodeup, _node}, state) do
    Logger.debug("#{inspect(node())} is UP!")
    :ok = Mndb.update()
    :ok = Mndb.connect(state[:mn_table], state[:disc_copy])
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, _node}, state) do
    Mndb.update()
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:mnesia_system_event, {:mnesia_up, _node}},
        %{disc_copy: copy, mn_table: m_table} = state
      ) do
    update()
    if copy, do: copy_schema(copy)
    ensure_table(m_table, copy)
    {:noreply, state}
  end

  @impl true
  def handle_info({:mnesia_system_event, message}, state) do
    Logger.info("#{inspect(message)}")

    with {:inconsistent_database, reason, _node} <- message do
      Logger.warn("Error: #{inspect(reason)} ")
      send(__MODULE__, {:stop, {:shutdown, :network}})
    end

    {:noreply, state}
  end

  # @impl true
  # def handle_info({:quit, {:shutdown, :network}}, state) do
  #   Logger.debug("stop")
  #   Mnesia.stop()
  #   {:stop, state}
  # end

  @impl true
  def terminate(_, _state) do
    Mnesia.stop()
    Logger.warn("GS Terminated")
  end

  ############### Mnesia functions ##########################
  def connect(name, disc_copy? \\ false) do
    Logger.debug("Starting")

    with {:disc_schema, :ok} <- {:disc_schema, copy_schema(disc_copy?)},
         {:create_table, :ok} <- {:create_table, ensure_table(name, disc_copy?)} do
      :ok
    else
      {:disc_schema, {:error, reason}} -> {:error, {:disc_schema, reason}}
      {:create_table, {:error, reason}} -> {:error, {:create_table, reason}}
      {:error, reason} -> {:error, reason}
      {:aborted, reason} -> {:aborted, reason}
    end
  end

  @doc """
  We declare fresh new nodes to Mnesia. The doc says: "this function must only be used to connect to newly started RAM nodes with an empty schema. If, for example, this function is used after the network has been partitioned, it can lead to inconsistent tables".
  """
  def update() do
    case :mnesia.change_config(:extra_db_nodes, Node.list()) do
      {:ok, [_t | _h]} ->
        # Logger.debug("Update: #{inspect(t)}, #{inspect(h)}")
        :ok

      {:ok, []} ->
        # Logger.debug("from []")
        :ok

      {:error, reason} ->
        Logger.debug("U@N: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  We ensure that the `:schema` table is of type `disc_copies` since a `ram_copies`type schema doesn't allow other disc-resident tables.
  """

  def copy_schema(disc_copy) do
    case disc_copy do
      true ->
        Mnesia.wait_for_tables([:schema], 1_000)

        case Mnesia.change_table_copy_type(:schema, node(), :disc_copies) do
          # Logger.debug("Schema of disc copy type #{inspect(node())}")
          {:atomic, :ok} -> :ok
          # Logger.debug("Schema already of disc copy type #{inspect(node())}")
          {:aborted, {:already_exists, :schema, _, _}} -> :ok
          # Logger.debug("schema: #{inspect(reason)}")
          {:aborted, reason} -> {:error, reason}
        end

      false ->
        :ok
    end
  end

  def ensure_table(name, disc_copy) do
    table =
      case disc_copy do
        true ->
          Mnesia.create_table(name,
            access_mode: :read_write,
            attributes: [:post_id, :data],
            disc_copies: [node()],
            type: :ordered_set
          )

        false ->
          Mnesia.create_table(:mcache,
            access_mode: :read_write,
            attributes: [:post_id, :data],
            type: :ordered_set
          )
      end

    :ok = Mnesia.wait_for_tables([name], 3_000)

    case table do
      # Logger.debug("#{inspect(name)} created #{inspect(node())}")
      {:atomic, :ok} ->
        :ok

      # Logger.debug("#{inspect(name)} already exists #{inspect(node())}")
      {:aborted, {:already_exists, _name}} ->
        remote_to_node(name, disc_copy)
        :ok

      # Logger.debug("Ensure Table: #{inspect(reason)}, #{inspect(node())}")
      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc """
  This one is needed to disc-copy the "remote" data table to the new node.
  """
  def remote_to_node(name, disc_copy) do
    type = unless disc_copy, do: :ram_copies, else: :disc_copies
    Logger.debug("in remote: #{inspect(type)}")

    with :ok <- Mnesia.wait_for_tables([name], 3_000) do
      case Mnesia.add_table_copy(name, node(), type) do
        # Logger.debug("Table copied #{inspect(node())}")
        {:atomic, :ok} -> :ok
        # Logger.debug("Table already copied, from Aborted, #{inspect(node())}")
        {:aborted, {:already_exists, _name, _node}} -> :ok
        # Logger.debug("Table already copied, from Error, #{inspect(node())}")
        {:error, {:already_exists, _table, _node, _}} -> :ok
        # Logger.debug("set type at node: #{inspect(reason)}, #{inspect(node())}")
        {:aborted, reason} -> {:error, reason}
      end
    else
      # Logger.debug(
      #     "Error remote copy #{inspect(name)}: #{inspect(reason)}, #{inspect(node())}"
      #   )
      {:error, reason} -> {:error, reason}
    end

    :ok
  end

  @impl true
  def handle_call({:data}, _from, %{mn_table: m_table} = state) do
    reply = unless :ets.whereis(:mcache) == :undefined, do: :ets.tab2list(m_table)
    {:reply, reply, state}
  end

  def ensure_stop() do
    case Mnesia.stop() do
      :stopped -> :ok
      _ -> check_stop()
    end
  end

  def check_stop() do
    case Mnesia.system_info(:is_running) do
      :no ->
        :ok

      :stopping ->
        Process.sleep(1_000)
        check_stop()

      _ ->
        {:error, :mnesia_not_stopping}
    end
  end
end
