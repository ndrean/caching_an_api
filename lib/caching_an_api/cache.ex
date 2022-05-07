defmodule Cache do
  use GenServer
  require EtsDb
  require MnDb
  require Logger

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

  ###########################################
  ## callbacks

  @doc """
  `GenServer.start_link` calls `GenServer.init` and passes the arguments "opts"
  that where set in "Application.ex".
  Note: the argument in `init` should match the 2d argument used in `GenServer.start_link`.

  The GenServer process subscribes to node status change messages (:nodeup, :nodedown)

  """
  @impl true
  def init(opts) do
    # subscribe to node changes
    :ok = :net_kernel.monitor_nodes(true)

    state = %{
      ets_table: opts[:ets_table],
      m_table: opts[:mn_table],
      store: opts[:store]
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:get, key}, _from, %{store: store} = state) do
    cache =
      case store do
        :mn ->
          MnDb.read(key)

        :ets ->
          EtsDb.get(key)

        :dcrdt ->
          nil

        nil ->
          state[key]
      end

    {:reply, cache, state}
  end

  @impl true
  def handle_cast({:put, key, data}, %{store: store} = state) do
    new_state =
      case store do
        :ets ->
          EtsDb.put(key, data)
          state

        :mn ->
          MnDb.write(key, data)
          state

        :dcrt ->
          nil

        nil ->
          Map.put(state, key, data)
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:nodeup, _node}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, _node}, state) do
    ##  reacting with ERLANG MONITOR NODE ":nodedown" in the Cache
    # alternatively,
    # react with MNESIA SYSTEM EVENT ":mnesia_down" in MnDb

    {:noreply, state}
  end
end
