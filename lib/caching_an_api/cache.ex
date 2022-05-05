defmodule Cache do
  use GenServer
  alias :ets, as: Ets
  require EtsDb
  require MnDb
  require Logger

  # @mn_table :mcache
  # @ets_table :ecache

  @doc """
  We pass config options set in the Application level and name the GenServer pid with the module name.
  """
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

  The GenServer process subscribes to node status change messages (:nodeup, :nodedown)

  """
  @impl true
  def init(opts) do
    store = opts[:store]
    ets_table = opts[:ets_table]
    m_table = opts[:mn_table]

    # subscribe to node changes
    :ok = :net_kernel.monitor_nodes(true)

    state = %{
      ets_table: ets_table,
      m_table: m_table,
      store: store
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    %{m_table: m_table, store: store} = state

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
          EtsDb.get(key)

        nil ->
          state[key]
      end

    {:reply, cache, state}
  end

  @impl true
  def handle_cast({:put, key, data}, state) do
    %{m_table: m_table, store: store} = state

    new_state =
      case store do
        :ets ->
          EtsDb.put(key, data)
          state

        :mn ->
          case MnDb.write(m_table, key, data) do
            {:atomic, :ok} -> state
            _ -> :aborted
          end

        nil ->
          Map.put(state, key, data)
      end

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
  def handle_info({:mnesia_system_event, message}, state) do
    Logger.info("#{inspect(message)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodeup, _node}, %{m_table: m_table} = state) do
    # Logger.info("Detected new node #{inspect(node)}")

    Process.sleep(100)
    MnDb.connect_mnesia_to_cluster(m_table)

    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, _node}, state) do
    # Logger.info("Node disconnected: #{inspect(node)}")
    MnDb.update_mnesia_nodes()

    {:noreply, state}
  end
end
