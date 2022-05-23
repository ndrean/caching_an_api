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
  :rpc.cal():"b@127.0.0.1", Mndb, :data, [])
  <=>
  GenServer.call({Mndb, :"b@127.0.0.1"}, {:data})
  for node <- Node.list(), do: {node, GenServer.call({Mndb, node}, {:data}) }
    ```

  """
  def data(), do: GenServer.call(__MODULE__, {:data})

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  ################ Server callbacks
  @doc """
  Flag to trap exit, enable Erlang monitor nodes, init Mnesia (schema, start, subscribe). A flag is added to trigger the GenServer that runs the `terminate` callback when going down.
  """
  @impl true
  def init(opts) do
    state = Enum.into(opts, %{})
    Process.flag(:trap_exit, true)

    with :ok <- :net_kernel.monitor_nodes(true),
         :ok <- ensure_start() do
      {:ok, state}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  ############ Mnesia functions
  def ensure_start() do
    :stopped = Mnesia.stop()

    if(Node.list() == [], do: Mnesia.create_schema([node()]))

    with {:start, :ok} <- {:start, Mnesia.start()},
         {:subscribe, {:ok, _node}} <- {:subscribe, Mnesia.subscribe(:system)} do
      :ok
    else
      {_, reason} ->
        send(__MODULE__, {:stop, reason})
    end
  end

  @doc """
  The first node sets the schema.
  Wnen Erlang EPMD sends a `:nodeup` event, we create a table and update Mnesia cluster.
  When Mnesia sends an UP event, we firstly update the cluster, then copy the schema on disc to allow tables to be created at the node, whether in RAM or on disc.
  """
  @impl true
  def handle_info({:nodeup, node}, state) do
    Logger.debug("Node #{inspect(node)} is UP")

    with {:create, {:ok, _node}} <- {:create, Mndb.create_table(state.mn_table, state.disc_copy)},
         {:update, {:ok, _node}} <- {:update, Mndb.update()} do
      {:noreply, state}
    else
      {:create, reason} ->
        send(__MODULE__, {:stop, {:create, reason}})

      {:udpate, reason} ->
        send(__MODULE__, {:stop, {:udpate, reason}})

      {_, reason} ->
        send(__MODULE__, {:stop, reason})
        {:noreply, state}
    end

    {:noreply, state}
  end

  # @impl true
  # def handle_info({:nodedown, _node}, state) do
  #   {:noreply, state}
  # end

  @impl true
  def handle_info(
        {:mnesia_system_event, {:mnesia_up, node}},
        state
      ) do
    Logger.notice("Mnesia is UP at #{inspect(node)}")

    with {:update, {:ok, _node}} <- {:update, Mndb.update()},
         {:copy_sch, {:ok, _node}} <- {:copy_sch, Mndb.copy_schema()},
         {:remote, {:ok, _node}} <-
           {:remote, Mndb.remote_to_node(state.mn_table, state.disc_copy)} do
      Logger.warn("Mnesia-up: #{inspect(Mndb.info())}")
    else
      {:update, {:error, reason}} ->
        send(__MODULE__, {:stop, {:update, reason}})

      {:copy_sch, {:error, reason}} ->
        send(__MODULE__, {:stop, {:copy_sch, reason}})

      {:remote, {:error, reason}} ->
        send(__MODULE__, {:stop, {:remote, reason}})

      {:error, reason} ->
        send(__MODULE__, {:stop, reason})
    end

    {:noreply, state}
  end

  # @impl true
  # def handle_info(
  #       {:mnesia_system_event, {:mnesia_down, _node}},
  #       state
  #     ) do
  #   {:noreply, state}
  # end

  @impl true
  def handle_info({:mnesia_system_event, message}, state) do
    Logger.info("#{inspect(message)}")

    with {:inconsistent_database, reason, _node} <- message do
      Logger.warn("Error: #{inspect(reason)} ")
      send(__MODULE__, {:stop, {:shutdown, :network}})
    end

    {:noreply, state}
  end

  @impl true
  def terminate(_, state) do
    Mnesia.stop()
    Logger.warn("GS Terminated")
    {:kill, state}
  end

  ############### Mnesia functions ##########################

  @doc """
  We declare fresh new nodes to Mnesia. The doc says: "this function must only be used to connect to newly started RAM nodes with an empty schema. If, for example, this function is used after the network has been partitioned, it can lead to inconsistent tables".
  """
  def update() do
    # Logger.debug("Update inspect init: #{inspect(node())}, #{inspect(Node.list())}")

    case Mnesia.change_config(:extra_db_nodes, Node.list()) do
      {:ok, _} ->
        {:ok, node()}

      {:error, reason} ->
        Logger.debug("No node: #{inspect(node())} - #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  We ensure that the `:schema` table is of type `disc_copies` since a `ram_copies`type schema doesn't allow other disc-resident tables.
  """

  def copy_schema() do
    # Logger.debug("Copy schema for: #{inspect(node)}")

    :ok = Mnesia.wait_for_tables([:schema], 1_000)

    case Mnesia.change_table_copy_type(:schema, node(), :disc_copies) do
      #
      {:atomic, :ok} ->
        # node = node()
        # Logger.debug("Schema of disc copy type #{inspect(node())}")
        {:ok, node()}

      #
      {:aborted, {:already_exists, :schema, _, _}} ->
        # node = node()
        # Logger.debug("Schema already of disc copy type #{inspect(node())}")
        {:ok, node()}

      #
      {:aborted, reason} ->
        Logger.debug("schema: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def create_table(name, disc_copy) do
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
      {:atomic, :ok} ->
        # Logger.debug("#{inspect(name)} created #{inspect(node())}")
        {:ok, node()}

      {:aborted, {:already_exists, _name}} ->
        # Logger.debug("#{inspect(name)} already exists #{inspect(node())}")
        {:ok, node()}

      {:aborted, reason} ->
        # Logger.debug("Ensure Table: #{inspect(reason)}, #{inspect(node())}")
        {:error, reason}
    end
  end

  @doc """
  This one is needed to disc-copy the "remote" data table to the new node.
  """
  def remote_to_node(name, disc_copy) do
    type = unless disc_copy, do: :ram_copies, else: :disc_copies
    # Logger.debug("#{inspect(node())}: in remote: #{inspect(type)}")

    with :ok <- Mnesia.wait_for_tables([name], 3_000) do
      case Mnesia.add_table_copy(name, node(), type) do
        {:atomic, :ok} ->
          # Logger.debug("Table copied #{inspect(node())}")
          # Process.sleep(500)
          # node = node()
          {:ok, node()}

        {:aborted, {:already_exists, _name, node}} ->
          # Logger.debug("Table already copied, from Aborted, #{inspect(node)}")
          # Logger.debug("Remote: #{inspect(node())},  #{inspect(Mndb.info())}}")
          # Process.sleep(500)
          {:ok, node}

        {:error, {:already_exists, _table, node, _}} ->
          # Logger.debug("Table #{table} already copied, from Error, #{inspect(node)}")
          # Logger.debug("Remote: #{inspect(node())},  #{inspect(Mndb.info())}}")
          # Process.sleep(500)
          {:ok, node}

        {:aborted, reason} ->
          Logger.debug("Can't set type at node: #{inspect(reason)}, #{inspect(node())}")
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def handle_call({:data}, _from, %{mn_table: m_table} = state) do
    reply = unless :ets.whereis(:mcache) == :undefined, do: :ets.tab2list(m_table)
    {:reply, reply, state}
  end
end
