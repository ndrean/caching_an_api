defmodule CacheGS do
  use GenServer
  # require EtsDb
  # require MnDb
  require Logger

  @doc """
  We pass config options set in the Application level and name the GenServer pid with the module name.
  """
  def start_link(opts) do
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

  def inverse(index, key) do
    GenServer.call(__MODULE__, {:inverse, index, key})
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
    state = opts

    docker? = Application.get_env(:caching_an_api, :docker)

    host = if(docker?, do: "redis", else: "127.0.0.1")

    case Redix.start_link(host: host, port: 6379) do
      {:ok, pid} ->
        with {:ok, "PONG"} <- Redix.command(pid, ["ping"]) do
          Logger.info("Redis is up")
        else
          {_, _} -> Logger.warn("no Redis")
        end

      {:error, %Redix.ConnectionError{reason: reason}} ->
        Logger.info("Redis error: #{reason}")
    end

    case opts[:store] do
      nil ->
        state = Enum.into(opts, %{}) |> Map.put(:req, %{})
        {:ok, state}

      _ ->
        {:ok, state}
    end
  end

  @impl true
  def handle_call({:inverse, index, key}, _from, state) do
    reply = if state[:store] == :mn, do: MnDb2.inverse(index, key, state[:mn_table])

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    cache =
      case state[:store] do
        :mn ->
          MnDb2.read(key, state[:mn_table])

        :ets ->
          EtsDb.get(key, state[:ets_table])

        :dcrdt ->
          nil

        nil ->
          state.req[key]
      end

    {:reply, cache, state}
  end

  @impl true
  def handle_cast({:put, key, data}, state) do
    state =
      case state[:store] do
        :ets ->
          EtsDb.put(key, data, state[:ets_table])
          state

        :mn ->
          MnDb2.write(key, data, state[:mn_table])
          state

        :dcrt ->
          nil

        nil ->
          %{state | req: Map.put(state.req, key, data)}
      end

    {:noreply, state}
  end

  @doc """
  Callback reacting to ERLANG MONITOR NODE `:nodedown` or `:nodeup` since we set `:net_kernel.monitor_nodes(true)` in the Cache module. Note that we also subscribed to Mnesia system event (with `:mnesia_down` or `:mnesia_up`). These are handled in the Mnesia module.
  """
  @impl true
  def handle_info({:nodeup, _node}, state) do
    MnDb2.connect_mnesia_to_cluster(state)

    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, _node}, state) do
    # MnDb2.update_mnesia_nodes()
    {:noreply, state}
  end

  @impl true
  def handle_info({:mnesia_system_event, message}, state) do
    Logger.info("#{inspect(message)}")

    with {:inconsistent_database, reason, _node} <- message do
      # Logger.critical("#{reason} at #{node}")
      Logger.warn("Error: #{inspect(reason)} ")
      System.cmd("say", ["bye to #{node() |> to_string() |> String.at(0)}"])
      send(__MODULE__, {:quit, {:shutdown, :network}})
    end

    {:noreply, state}
  end

  def handle_info({:quit, {:shutdown, :network}}, state) do
    {:stop, :shutdown, state}
  end
end
