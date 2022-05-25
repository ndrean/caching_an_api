# new
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

  ########### @
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

  ###################

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  ################ callbacks
  @doc """
  Flag to trap exit, enable Erlang monitor nodes, init Mnesia (schema, start, subscribe). A flag is added to trigger the GenServer that runs the `terminate` callback when going down.
  """
  @impl true
  def init(opts) do
    state = Enum.into(opts, %{})
    Process.flag(:trap_exit, true)

    with {:epmd, :ok} <- {:epmd, :net_kernel.monitor_nodes(true)},
         {:ensure_start, {:ok, _node}} <- {:ensure_start, ensure_start(state.disc_copy)} do
      {:ok, state}
    else
      {:epmd, {:error, reason}} -> {:error, {:epmd, reason}}
      {:ensure_start, {:error, reason}} -> {:error, {:ensure_start, reason}}
      {:error, reason} -> {:error, reason}
    end
  end

  ############ Mnesia functions

  def ensure_start(disc_copy) do
    :stopped = Mnesia.stop()
    # if no disc exists, the Schema can't by a disc_copy, so tables can't be disc_copy

    # Logger.debug("check 1: #{inspect(Mndb.check_dir(disc_copy))}")

    if(Node.list() == [], do: Mnesia.create_schema([node()]))

    with :ok <- Mnesia.start(),
         :ok <- wait_for_start(),
         {:ok, node} <- Mnesia.subscribe(:system),
         {:copy, true} <- {:copy, Mndb.check_dir_start(disc_copy)} do
      # Logger.debug("check 21: #{inspect(Mndb.check_dir_start(disc_copy))}")
      {:ok, node}
    else
      {:copy, false} ->
        send(__MODULE__, {:copy, "no disc"})
        {:ok, node()}

      {:error, reason} ->
        {:stop, {:shutdown, reason}}
    end
  end

  @doc """
  The first node sets the schema.
  Wnen Erlang EPMD sends a `:nodeup` event, we create a table and update Mnesia cluster.
  When Mnesia sends an UP event, we firstly update the cluster, then copy the schema on disc to allow tables to be created at the node, whether in RAM or on disc.
  """

  @impl true
  def handle_info({:copy, "no disc"}, state) do
    Logger.debug("No disc, setup your config")
    # killer(:copy, "no disc", state)
    # {:stop, {:shutdown, {:copy, "no disc"}, state}}
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, _node}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    [t | h] = Node.list()

    Logger.debug(
      "t: #{inspect(t)}, h: #{inspect(h)}, Node UP!, node: #{inspect(node)}, node(): #{inspect(node())}, Node.list: #{inspect(Node.list())}, running: #{inspect(Mnesia.system_info(:running_db_nodes))}"
    )

    with {:create, {:ok, _node}} <-
           {:create, Mndb.create_table(node(), state.mn_table, state.disc_copy)},
         {:update, {:ok, _node}} <- {:update, Mndb.update(Node.list())} do
      for node <- Node.list() do
        Mndb.remote_to_node(node, state.mn_table, state.disc_copy)
        # {:remote, {:ok, node}} <-

        #   {:remote, }
      end

      {:noreply, state}
    else
      {:create, {:error, reason}} ->
        killer(:create, reason, state)

      # {:stop, {:shutdown, {:create, reason}}, state}

      {:udpate, {:error, reason}} ->
        killer(:update, reason, state)

      # {:stop, {:shutdown, {:update, reason}}, state}

      {_err, reason} ->
        {:stop, {:shutdown, reason}, state}
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:mnesia_system_event, {:mnesia_up, node}},
        state
      ) do
    unless node == node() do
      with {:copy_sch, {:ok, node}} <- {:copy_sch, Mndb.copy_schema(node)},
           {:update, {:ok, _node}} <- {:update, Mndb.update(Node.list())},
           {:remote, {:ok, node}} <-
             {:remote, Mndb.remote_to_node(node, state.mn_table, state.disc_copy)} do
        Logger.warn(
          "Mnesia UP: node #{inspect(node)} from #{inspect(node())}: #{inspect(Mndb.info())} "
        )

        Process.sleep(1_000)
        :ok
      else
        {:update, {:error, reason}} ->
          killer(:update, reason, state)

        # {:stop, {:shutdown, {:update, reason}}, state}

        {:copy_sch, {:error, reason}} ->
          killer(:error, reason, state)

        # {:stop, {:shutdown, {:copy_sch, reason}}, state}

        {:remote, {:error, reason}} ->
          killer(:remote, reason, state)

        # {:stop, {:shutdown, {:remote, reason}}, state}

        {:error, reason} ->
          {:stop, {:shutdown, reason}, state}
      end
    end

    # end

    {:noreply, state}
  end

  @impl true
  def handle_info({:mnesia_system_event, message}, state) do
    Logger.info("#{inspect(message)}")

    with {:inconsistent_database, reason, _node} <- message do
      Logger.warn("Error: #{inspect(reason)} ")
      killer(:inconsistent_db, reason, state)
      # {:stop, {:shutdown, {:inconsistent_db, reason}}, state}
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Catch all: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Mnesia.stop()
    Logger.warn("GS Terminated with #{inspect(reason)}")
  end

  ############### Mnesia functions ##########################

  @doc """
  We declare fresh new nodes to Mnesia. The doc says: "this function must only be used to connect to newly started RAM nodes with an empty schema. If, for example, this function is used after the network has been partitioned, it can lead to inconsistent tables".
  """
  def update(nodes) do
    case Mnesia.change_config(:extra_db_nodes, nodes) do
      {:ok, _} ->
        {:ok, node()}

      {:error, reason} ->
        Logger.debug("No node: #{inspect(node())} - #{inspect(reason)}")
        killer(:udpate, reason, nil)
        # {:stop, {:shutdown, {:update, :no_node}}, nil}
    end
  end

  @doc """
  We ensure that the `:schema` table is of type `disc_copies` since a `ram_copies`type schema doesn't allow other disc-resident tables.
  """

  def copy_schema(node) do
    :ok = Mnesia.wait_for_tables([:schema], 1_000)

    case Mnesia.change_table_copy_type(:schema, node, :disc_copies) do
      {:atomic, :ok} ->
        # Logger.debug("Schema of disc copy type #{inspect(node())}")
        {:ok, node}

      {:aborted, {:already_exists, :schema, _, _}} ->
        # Logger.debug("Schema already of disc copy type #{inspect(node())}")
        {:ok, node}

      {:aborted, reason} ->
        Logger.debug("schema: #{inspect(reason)}")
        killer(:copy_sch, reason, nil)
        # {:stop, {:shutdown, {:copy_sch, reason}}, nil}
    end
  end

  def create_table(node, name, disc_copy) do
    table =
      case disc_copy do
        true ->
          :mnesia.create_table(:mcache,
            access_mode: :read_write,
            attributes: [:post_id, :data],
            disc_copies: [node],
            type: :ordered_set
          )

        false ->
          Mnesia.create_table(:mcache,
            access_mode: :read_write,
            attributes: [:post_id, :data],
            type: :ordered_set
          )
      end

    # Logger.debug("#{inspect(Mndb.info())}")
    :ok = Mnesia.wait_for_tables([name], 3_000)

    case table do
      {:atomic, :ok} ->
        {:ok, node}

      {:aborted, {:already_exists, _name}} ->
        {:ok, node}

      {:aborted, reason} ->
        killer(:create, reason, nil)
        # {:stop, {:shutdown, {:aborted, reason}}, nil}
    end
  end

  @doc """
  This one is needed to disc-copy the "remote" data table to the new node.
  """
  def remote_to_node(node, names, disc_copy) do
    type = unless disc_copy, do: :ram_copies, else: :disc_copies

    with :ok <- Mnesia.wait_for_tables([names], 3_000) do
      case Mnesia.add_table_copy(names, node, type) do
        {:atomic, :ok} ->
          {:ok, node}

        {:aborted, {:already_exists, _name, node}} ->
          Logger.debug("#{inspect(node)}: copy 1")
          {:ok, node}

        {:error, {:already_exists, _table, node, _}} ->
          Logger.debug("#{inspect(node)}: copy 2")
          {:ok, node}

        {:aborted, reason} ->
          Logger.debug("Can't set type at node: #{inspect(reason)}, #{inspect(node)}")
          {:stop, {:shutdown, {:aborted, reason}}, reason}
      end
    else
      {:error, reason} -> {:stop, {:shutdown, {:error, reason}}, nil}
    end
  end

  def check_dir_start(copy) do
    # dir? = Mnesia.system_info(:directory) |> File.exists?()
    dir? = Mnesia.system_info(:use_dir)
    check_first_node = Node.list() == [] && copy

    case check_first_node do
      true -> if(dir?, do: true, else: false)
      false -> true
    end
  end

  def wait_for_start do
    case Mnesia.system_info(:is_running) do
      :yes ->
        :ok

      :no ->
        {:error, :mnesia_unexpectedly_stopped}

      :stopping ->
        {:error, :mnesia_unexpectedly_stopping}

      :starting ->
        Process.sleep(1_000)
        wait_for_start()
    end
  end

  def killer(step, reason, state) do
    {:stop, {:shutdown, {step, reason}}, state}
  end

  ############################
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

  @impl true
  def handle_call({:data}, _from, %{mn_table: m_table} = state) do
    reply = unless :ets.whereis(:mcache) == :undefined, do: :ets.tab2list(m_table)
    {:reply, reply, state}
  end

  ###################
end
