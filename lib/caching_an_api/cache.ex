defmodule CachingAnApi.Cache do
  use GenServer
  alias :ets, as: Ets
  require EtsDb
  require MnDb
  require Logger

  # @mn_table :mcache
  # @ets_table :ecache

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sync call
  """
  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  @doc """
  Cast is an Async update since we don't inform the client
  """
  def put(key, data) do
    GenServer.cast(__MODULE__, {:put, key, data})
  end

  @doc """
  Cast is an Async deletion since we don't inform the client
  """
  def del(key), do: GenServer.cast(__MODULE__, {:del, key})

  ###########################################
  ## GenServer callbacks

  @doc """
  `GenServer.start_link` calls `GenServer.init` and passes the arguments "opts"
  that where set in "Application.ex".
  Note: the argument in `init` should match the 2d argument used in `GenServer.start_link`.
  """
  @impl true
  def init(opts) do
    store = opts[:store]
    ets_table = opts[:ets_table]
    mn_table = opts[:mn_table]

    # Get notified when new nodes are connected.
    :ok = :net_kernel.monitor_nodes(true)

    # init the ETS store
    case et = EtsDb.setup(ets_table) do
      _ -> Logger.info("Ets cache up: #{et}")
    end

    # if Mnesia.system_info(:running_db_nodes) == [node()], do: MnDb.local_start(mn_table)

    state = %{
      ets_table: ets_table,
      m_table: mn_table,
      store: store,
      cache_on: opts[:cache_on]
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    %{ets_table: ets_table, m_table: m_table, store: store} = state

    cache =
      case store do
        :mn ->
          case MnDb.read(m_table, key) do
            {:atomic, data} ->
              data

            {:aborted, data} ->
              {:aborted, data}
          end

        :ets ->
          case :ets.lookup(ets_table, key) do
            [] -> nil
            [{^key, data}] -> data
            _ -> :error
          end

        nil ->
          nil
      end

    {:reply, cache, state}
  end

  :mnesia.set_master_nodes(:mcache, Node.list())

  @impl true
  def handle_cast({:put, key, data}, state) do
    %{ets_table: ets_table, m_table: m_table, store: store, cache_on: cache_on} = state

    if cache_on do
      case store do
        :ets ->
          Ets.insert(ets_table, {key, data})

        :mn ->
          case MnDb.write(m_table, key, data) do
            {:atomic, :ok} -> :ok
            _ -> :aborted
          end
      end
    end

    new_state = Map.put(state, key, data)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:del, key}, state) do
    %{ets_table: ets_table, m_table: _m_table} = state

    Ets.delete(ets_table, key)

    new_state = Map.delete(state, key)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:nodeup, _node}, %{m_table: m_table} = state) do
    Logger.info("new node")
    MnDb.connect_mnesia_to_cluster(m_table)

    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, node}, state) do
    Logger.info("Node disconnected: #{inspect(node)}")

    MnDb.update_mnesia_nodes()

    {:noreply, state}
  end
end
