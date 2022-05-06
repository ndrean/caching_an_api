# CachingAnApi & Concurrency

We cache the responses to HTTP calls with a GenServer, the Ets data store and the Mnesia database in a distributed cluster. It only makes sense to use the state of a process or a local Ets store since this type of cache is proper to each node by nature. However, we change a field in the response on the first call, and we want to propagate the updated response to the cluster thanks to the TCP connection between each node without the need of new HTTP calls.

> Other unused options here would rely on external databases, such as Redis with PubSub or Postgres with Listen/Notify. Finally, as a last option, in case you have a web interface, you can use websockets to broadcast the modification to each local instance and store it accordingly.

There is a module Api for performing HTTP requests that calls a Cache module.
You can configure which store is used: the state of the Cache GenServer, Ets or Mnesia. Set the `store: type` with `:mn` or `:ets` or nothing (for the process state).

Ets and Mnesia are both run in their own supervised process.

## The stores

We have 3 choices to handle state:

- GenServer:
Basicaly, you could just use a GenServer to cache the HTTP requests as state. We have clients functions and server-side callbacks. State is passed and modifed with corresponding `handle_call` and `handle_cast` to the client functions. Furthermore, we can react to e.g. process calls with `handle_info`. This will be the case in the cluster mode when the Erlang VM will detect a node event. We will instanciate a copy of Mnesia from a `handle_info`.
A GenServer can be supervised but the data is lost.

- [ETS](https://www.erlang.org/doc/man/ets.html)
It is an in-build in-memory key-value database localized in a node and linked to the health of the calling process in a node: it lives and dies with an individual process.
The data store is **not distributed**: other nodes within a cluster can't access to it.
Data is saved with tuples and there is no need to serialize values.
Check for the improved [ConCache](https://github.com/sasa1977/con_cache) with TTL support.

> What's the point of using Ets? It allows shared, concurrent access to data. When using the flag `:public`, we can use it outside of the process that created it within a node. However, it's life shelf is fully dependent on the managing GenServer.

- [Mnesia](http://erlang.org/documentation/doc-5.2/pdf/mnesia-4.1.pdf)
Mnesia is an in-build distributed in-memory and disc persisted (optional) database build for concurrency. It work both in memory (with Ets) and on disc . As Ets, it stores tuples.
In Mnesia, every action needs to be wrapped within a **transaction**. If something goes wrong with executing a transaction, it will be rolled back and nothing will be saved on the database.

- storage capacity:
From the [doc](https://www.erlang.org/faq/mnesia.html), it is indicated that:
  - for ram_copies and disc_copies, the entire table is kept in memory, so data size is limited by available RAM.
  - for disc_copies tables, the entire table needs to be read from disk to memory on node startup, which can take a long time for large table.

- `:atomic` means that all operations should occur or no operations should occur in case of an error.

> What's the point of using Mnesia? It works in a cluster, both in RAM and disc. The data are replicated on each node, available concurrently and persisted. Furthermoe, if you need to keep a database that will be used by multiple processes and/or nodes, using Mnesia means you don't have to write your own access controls.

A [word about scalability performance of Mnesia](http://www.dcs.gla.ac.uk/~amirg/publications/DE-Bench.pdf) and [here](https://stackoverflow.com/questions/5044574/how-scalable-is-distributed-erlang) and [Erlang nodes](https://stackoverflow.com/questions/5044574/how-scalable-is-distributed-erlang).

## Connecting machines

From **code**, if you want to connect two machines "a@node" and "b@node" with respective IP of 192.168.0.1 and 192.168.0.2, then **within code** you would do:

```elixir
# on the "a@node@ macihe, 
Node.start :"a@192.168.0.1" 
Node.set_cookie :cookie_name
Node.connect "b@192.168.0.2"

# on the "b@node" machine
Node.start :"b@192.168.0.2" 
Node.set_cookie :cookie_name
```

From an **IEX** session, use the flag `--sname` (for short name) and it will assign **:"a@your-local-system-name"**. If you use instead the flag `--name`, then use **:"a@127.0.0.1"** or **:"a@example.com"**.

```bash
$ iex --sname a -S mix
#iex> iex --sname a --erl "-connect_all false" --cookie cookie_s -S  mix
```

or

```bash
iex> iex --name a@127.0.0.1  -S mix
[...{:mnesia_up, :"a@127.0.0.1"}...]
iex> iex --name b@127.0.0.1  -S mix
[...]
iex(a@127.0.0.1)> :net.ping(:"b@127.0.0.1")
:pong
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
#! /bin/bash
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

Elixir school [Ets](https://elixirschool.com/en/lessons/storage/ets)

<https://sayan.xyz/posts/elixir-erlang-and-ets-alchemy>

The startup is straightforward. Just use `ets.new`. Then you may use `ets.lookup` and `ets.insert` to respectively "get" and "put".

> To display the usage of `:public`, we made a module EtsDb as a GenServer with Supervision. This makes the Ets process independant from the Cache module. Since the table is `:public`, we can use it from any process. Tthe supervision allows the Ets to be restarted in case of problems.

## Mnesia

### Configuration

All you need is to give **names** to tables and a **folder location** for each node for the disc copies.

> the documentation says that "the directory must be UNIQUE for each node. "Two nodes must never share the same directory".

You can add a node specific name in the "config/confi.exs" file. For example: `config :mnesia, dir: 'mndb_#{Node.self()}'`. The "config/config.exs" is used at **build time**, before compilation and dependencies loading).
If the folder doesn't exist, it will be created.

### Sources

The [Mnesia](http://erlang.org/documentation/doc-5.2/pdf/mnesia-4.1.pdf) documentation.

The [Elixir school lesson](https://elixirschool.com/en/lessons/storage/mnesia)

Other usefull links:

<https://mbuffa.github.io/tips/20201111-elixir-troubleshooting-mnesia/>

<https://www.welcometothejungle.com/fr/articles/redis-mnesia-distributed-database>

<https://code.tutsplus.com/articles/store-everything-with-elixir-and-mnesia--cms-29821>

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

### Locks

To ensure that there are no race conditions, you can use locks.

- `:write`, which prevents other transactions from acquiring a lock on a resource,

- `:read`, which allows other nodes to obtain only `:read` locks.

If someone has a write lock, no one can acquire either a read lock or a write lock at the same item.

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

- no cache

Comparison:
enum_yield_many                   11.06
asynced_stream                     2.72 - 4.07x slower +0.28 s
stream_synced                      0.83 - 13.33x slower +1.12 s
yield_many_asynced_stream          0.65 - 17.02x slower +1.45 s

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
