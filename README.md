# CachingAnApi & Concurrency

We cache the responses to HTTP calls with a GenServer, an Ets data store and a Mnesia database in the case of a distributed cluster and a CRDT solution.
It would only make sense to use the state of a process or a local Ets store to cache HTTP calls since it is proper to each node by nature. However, we change a field in the response on the first call. We can propagate the updated response to the other nodes in cluster thanks to the TCP connection between each node, so that we save on new HTTP calls.

> Other unused options here would rely on external databases, such as Redis with PubSub or Postgres with Listen/Notify.

There is a supervised module Api for performing HTTP requests that calls a Cache module.
You can configure which store is used: the state of the Cache GenServer, Ets or Mnesia. Set the `store: type` with `:mn` or `:ets` or `crdt` or nothing (for the process state).

Ets and Mnesia are both run in their own supervised process.

## The stores

We have 4 choices to handle state:

- GenServer:
Basicaly, you could just use a GenServer to cache the HTTP requests as state. We have clients functions and server-side callbacks. State is passed and modifed with corresponding `handle_call` and `handle_cast` to the client functions. Furthermore, we can react to e.g. process calls with `handle_info`. This will be the case in the cluster mode when the Erlang VM will detect a node event.
A GenServer can be supervised but the data is lost.

- [ETS](https://www.erlang.org/doc/man/ets.html)
It is an in-build in-memory key-value data store localized in a node and it's life shelf is dependant upon the process that created it: it lives and dies with an individual process.
The data store is **not distributed**: other nodes within a cluster can't access to it.
Data is saved with tuples and there is no need to serialize values.
The default flag `:protected` means that any process can read from the Ets database whilst only the Ets process can write. It then offers shared, concurrent read access to data (meaning scaling upon the number of CPUs used).

> Check for the improved [ConCache](https://github.com/sasa1977/con_cache) with TTL support.

- [Mnesia](http://erlang.org/documentation/doc-5.2/pdf/mnesia-4.1.pdf)
Mnesia is an in-build distributed in-memory and optionnally node-based disc persisted database build for concurrency. It work both in memory (with Ets) and on disc. As Ets, it stores tuples. You can define tables whose structure is defined by a record type.
In Mnesia, every action needs to be wrapped within a **transaction**. If something goes wrong with executing a transaction, it will be rolled back and nothing will be saved on the database.

  - storage capacity: from the [doc](https://www.erlang.org/faq/mnesia.html), it is indicated that:
    - for ram_copies and disc_copies, the entire table is kept in memory, so data size is limited by available RAM.
    - for disc_copies tables, the entire table needs to be read from disk to memory on node startup, which can take a long time for large table.

  - `:atomic` means that all operations should occur or no operations should occur in case of an error.

> What's the point of using Mnesia? It works in a cluster, both in RAM and disc. The data are replicated on each node, available concurrently and persisted. Furthermoe, if you need to keep a database that will be used by multiple processes and/or nodes, using Mnesia means you don't have to write your own access controls. Furthermore, a [word about scalability performance of Mnesia](http://www.dcs.gla.ac.uk/~amirg/publications/DE-Bench.pdf) and [here](https://stackoverflow.com/questions/5044574/how-scalable-is-distributed-erlang) and [here](https://stackoverflow.com/questions/5044574/how-scalable-is-distributed-erlang).

- [CRDT](https://github.com/derekkraan/delta_crdt_ex)
DeltaCrdt implements a key/value store using concepts from Delta CRDTs. A CRDT can be used as a distributed temporary caching mechanism that is synced across our Cluster. A good introduction to [CRDT](https://moosecode.nl/blog/how_deltacrdt_can_help_write_distributed_elixir_applications).

## Connecting machines

From **code**, if you want to connect two machines "a@node" and "b@node" with respective IP of 192.168.0.1 and 192.168.0.2, then **within code** you would do:

```elixir
# on the "a@node@ machine, 
Node.start :"a@192.168.0.1" 
Node.set_cookie :cookie_name
Node.connect "b@192.168.0.2"

# on the "b@node" machine
Node.start :"b@192.168.0.2" 
Node.set_cookie :cookie_name
```

From an **IEX** session, use the flag `--sname` (for short name) and it will assign **:"a@your-local-system-name"**. If you use instead the flag `--name`, then use **:"a@127.0.0.1"** or **:"a@example.com"**.

```bash
> iex --sname a -S mix
> iex --sname a --cookie cookie_s -S  mix
```

or

```bash
# Term 1
> iex --name a@127.0.0.1  -S mix
[...{:mnesia_up, :"a@127.0.0.1"}...]
iex(a@127.0.0.1)> :net.ping(:"b@127.0.0.1")
:pong

# Term 2
> iex --name b@127.0.0.1  -S mix
[...]
```

or with the compiled code:

```bash
# file vm.args contains name and cookie
./bin/...
```

## Run IEX sessions in new terminals

> a `Process.sleep(100)` is needed for the nodes to connect (in the `handle_info` callback in the Cache GenServer)

On MacOS, `chmod +x` the following:

```bash
# launcher.sh
# ! /bin/bash
for i in a b c d
do
    osascript -e "tell application \"Terminal\" to do script \"iex --sname "$i" -S mix\""
done
```

Alternatively, use [ttab](https://www.npmjs.com/package/ttab)

```bash
host="@127.0.0.1"
for i in a1 b1 c1
do
  ttab iex name "$i$host" -S mix
end
```

## Ets

Some documents about the data store: [Elixir-lang-org: Ets](https://elixir-lang.org/getting-started/mix-otp/ets.html), and [Elixir school: Ets](https://elixirschool.com/en/lessons/storage/ets) and an excellent article talking about [Ets in production](https://sayan.xyz/posts/elixir-erlang-and-ets-alchemy).

Some useful commands:

- creation: just use `:ets.new`
- read/write: `:ets.lookup` and `:ets.insert` to respectively "get" and "put"
- read all data of the table ":ecache": `:ets.tab2list(:ecache)`

### Check that the EtsDb GenServer module is supervised

```elixir
[Info] Ets cache up: ecache
iex> Process.whereis(EtsDb)
#PID<0.339.0>
iex> |> Process.exit(:shutdown)
:ok
[Info] Ets cache up: ecache
iex> Process.whereis(EtsDb)
#PID<0.344.0>
```

> The Ets process is wrapped into a GenServer. It can be accessed from the Cache module or the Api module. The DnymaicSupervision allows the Ets to be restarted in case of problems.

## Mnesia

### Configuration

All you need is to give **names** to tables and a **folder location** for each node for the disc copies.

> the documentation says that "the directory must be UNIQUE for each node. "Two nodes must never share the same directory".

You can add a node specific name in the "config/confi.exs" file. For example: `config :mnesia, dir: 'mndb_#{Node.self()}'`. The "config/config.exs" is used at **build time**, before compilation and dependencies loading).
If the folder doesn't exist, it will be created.

### Sources

The [Mnesia](http://erlang.org/documentation/doc-5.2/pdf/mnesia-4.1.pdf) documentation and the [Elixir school lesson](https://elixirschool.com/en/lessons/storage/mnesia). Also [LearnYouSomeErlang](https://learnyousomeerlang.com/mnesia#whats-mnesia).

Usefull libraries:

- [library Mnesiac](https://github.com/beardedeagle/mnesiac/blob/master/lib/mnesiac/store_manager.ex)
- [Library Amensia](https://github.com/meh/amnesia)

Other [nice source](https://mbuffa.github.io/tips/20201111-elixir-troubleshooting-mnesia/) or [here](https://www.welcometothejungle.com/fr/articles/redis-mnesia-distributed-database) and a bit about [amensia](https://code.tutsplus.com/articles/store-everything-with-elixir-and-mnesia--cms-29821).

Mnesia can be started in code with `:mnesia.start()`. We can add `:mnesia` in the MixProject application `included_application` to remove the VSCode warnings. Not adding it in `extra_application` is mandatory in single node mode since we need to create the schema before starting Mnesia.

### Mnesia system event handler

We use the Mnesia system event handler by declaring `:mnesia.subscribe(:system)`. We have a `handle_info` call in the Cache module to log the message.

### Single node mode startup

> DONT add `:mnesia` in the MixProject application `:extra_applications` since you will need to start it manually. Instead, add `included_applications: [:mnesia]`. This will also remove the warnings in VSCode. The reason is that you need to firstly create the schema (meaning you create the database), and only then start Mnesia.

The sequence is:

1. `:mnesia.create_schema` to create a new database.

2. `:mnesia.start()`

3. `:mnesia.create_table` where you specify the rows and also that you want a disc copy for your node. The parameter `disc_copies: [node()]` means that data is stored both on disc and in the memory.

4. The disc copy directory can be specified in the `config.exs` file.

### Distributed Mnesia startup

The sequence is:

- start Mnesia. Two options: declare `[extra_applications: [:mnesia]` in MixProject  or use `:mnesia.start()`.
- connect nodes and inform Mnesia that other nodes belong to the cluster,
- ensure that data (schema and table) are stored on disc. Two copy functions are used, depending if it's the schema or table.

```elixir
def connect_mnesia_to_cluster(name) do   
    # intial state
    -> on a@node
    running db nodes   = []
    stopped db nodes   = [a@MacBookND]

    -> on b@node
    running db nodes   = [a@MacBookND,b@MacBookND]
    remote             = [mcache]
    ram_copies         = [schema]
    disc_copies        = []
    [{a@MacBookND,disc_copies}] = [mcache]
    [{a@MacBookND,disc_copies},{b@MacBookND,ram_copies}] = [schema]

    :mnesia.start()
      -> on a@node
      opt_disc. Directory "../mndb_a@MacBookND" is NOT used
      running db nodes   = [a@MacBookND]
      remote             = []
      ram_copies         = [schema]
      disc_copies        = []
      [{a@MacBookND,ram_copies}] = [schema]

      -> on b@node
      opt_disc. Directory "../mndb_b@MacBookND" is NOT used
      running db nodes   = [a@MacBookND,b@MacBookND]
      remote             = [mcache]
      ram_copies         = [schema]
      disc_copies        = []
      [{a@MacBookND,disc_copies}] = [mcache]
      [{a@MacBookND,disc_copies},{b@MacBookND,ram_copies}] = [schema]

    :mnesia.change_config(:extra_db_nodes, Node.list())
    # => connects nodes and copies the schema in RAM to the new connected node
      -> on a@node
      opt_disc. Directory "../mndb_a@MacBookND" is NOT used
      running db nodes   = [a@MacBookND]
      remote             = []
      ram_copies         = [schema]
      disc_copies        = []
      [{a@MacBookND,ram_copies}] = [schema]

      -> on b@node
      opt_disc. Directory "../mndb_b@MacBookND" is NOT used
      running db nodes   = [b@MacBookND,a@MacBookND]
      remote             = [mcache]
      ram_copies         = [schema]
      disc_copies        = []
      [{a@MacBookND,ram_copies},{b@MacBookND,ram_copies}] = [schema]


    :mnesia.change_table_copy_type(:schema, node(), :disc_copies)
      -> on a@node
      opt_disc. Directory "../mndb_a@MacBookND" is used
      remote             = []
      ram_copies         = []
      disc_copies        = [schema]
      [{a@MacBookND,disc_copies}] = [schema]

      -> on b@node
      opt_disc. Directory "../mndb_b@MacBookND" is used
      running db nodes   = [b@MacBookND,a@MacBookND]
      remote             = [mcache]
      ram_copies         = []
      disc_copies        = [schema]
      [{a@MacBookND,disc_copies}] = [mcache]
      [{a@MacBookND,disc_copies},{b@MacBookND,disc_copies}] = [schema]

    
    :mnesia.create_table(:table,attributes...,disc_copies: [node()]) 
      -> on a@node
      remote             = []
      ram_copies         = []
      disc_copies        = [mcache,schema]
      [{a@MacBookND,disc_copies}] = [mcache, schema]

      -> on b@node
      remote             = [mcache]
      ram_copies         = []
      disc_copies        = [schema]
      [{a@MacBookND,disc_copies},{b@MacBookND,disc_copies}] = [schema]


    :mnesia.add_table_copy(:table, node(), :disc_copies)
      remote             = []
      ram_copies         = []
      disc_copies        = [mcache,schema]
      [{a@MacBookND,disc_copies},{b@MacBookND,disc_copies}] = [schema,mcache]
end
  ```

Code used:

```bash
:mnesia.system_info()
MnDb.ensure_start(name)
:mnesia.system_info()
MnDb.update_mnesia_nodes()
:mnesia.system_info()
MnDb.ensure_table_from_ram_to_disc_copy(:schema)
:mnesia.system_info()
MnDb.ensure_table_create(name)
:mnesia.system_info()
MnDb.ensure_table_copy_exists_at_node(name)
:mnesia.system_info()
```

## Cluster creation

The Erlang VM creates single TCP connections between nodes. For the clusterisation, you can use use `libcluster`:

- set the `gossip` topology for automatic DNS
- use `:net_kernel.monitor_nodes(true)`in `GenServer.start_link` to discover the nodes
- launch a node named "a@my_machine_ip" in IEX: `iex --name a@127.0.0.1 -S mix`

## Debug

Use `:mnesia.system_info()` to inspect Mnesia in an IEX session. You can also extract info using args. You can also use it in code.

```bash
iex> :mnesia.system_info()
[...]
iex> :mnesia.system_info(:running_db_nodes)
'[:a@127.0.0.1, :b@127.0.0.1]'
iex> :mnesia.system_info(:directory)
'.../mndb_test@mycomputer'
iex> :mnesia.table_info(:mcache, :attributes)
[:post_id, :data]
```

To inspect a **GenServer** state, you can use Erlang's `:sys.get_state(genserver_pid)`. We can get the pid with `Process.whereis(Cache)` since we named it.

In the code, you can add `IO.inspect(value, label: "check 1")` or `IO.inspect(binding())` (for a function arguments). Also `Logger.info("#{inspect(state)}")`.

## RESULTS

Used `benchee` to run `mix run lib/caching_an_api/benchmark.exs`.

- Cached. The cache is populated with the first pass of the slowest, `yield_many_asynced_stream`).

Comparison:
stream_synced                    2.88 K
enum_yield_many                  1.63 K - 1.76x slower +264.55 μs
asynced_stream                   1.02 K - 2.82x slower +633.34 μs
yield_many_asynced_stream        1.00 K - 2.87x slower +651.90 μs

## Misc notes

### Elixir notes

[handle_continue](https://elixirschool.com/blog/til-genserver-handle-continue/)

### Production release

```bash
mix phx.gen.secret
xxxx
export SCRET_KEY_BASE="xxxx"
MIX_ENV=prod mix setup
MIX_ENV=prod mix release
```

### Enum vs Stream

`Stream` evaluates the functions of the chain for each enumerable, whereas `Enum` evaluates each enumerable then performs the next function of the chain.

```elixir
iex> [1,2,3]|> Stream.map(&IO.inspect/1) |> Stream.map(&IO.inspect/1) |> Enum.to_list
1,1,2,2,3,3,
iex>  [1,2,3]|> Enum.map(&IO.inspect/1) |> Enum.map(&IO.inspect/1)
1,2,3,1,2,3
```

### Bakeware

<https://www.youtube.com/watch?v=ML5hQjPQL7A>

<https://github.com/bake-bake-bake/bakeware>
