# CachingAnApi

We cache the responses to API calls.

- within a GenServer that holds in the state the HTTP responses. The client operations are transfered to the server via callbacks. If it comes to crash, the data is lost

- within an ETS data store. It is an in-memory key-value database localized within a node.The data store is not distributed: other nodes within a cluster can't access to it.

- within a distributed Mnesia data store. It stores tuples inside tables,

## Cluster creation

```bash
# use the flag --sname (for short name) and it will assign :a@your-local-system-name
# if you don't use use the short name but the flag --name, then a@example.com
$ iex --sname a -S mix
iex> Node.connect(:a@MacBookND)
```

## Mnesia

<https://mbuffa.github.io/tips/20201111-elixir-troubleshooting-mnesia/>

<https://www.welcometothejungle.com/fr/articles/redis-mnesia-distributed-database>

<https://code.tutsplus.com/articles/store-everything-with-elixir-and-mnesia--cms-29821>

Both schema and table can be already created when you run your app, since Mnesia keeps RAM and disk copies, depending on how you configure it.

DONT add `:mnesia` in `CachingAnApi.MixProject.application[:extra_applications]` since you will need to start it manually. Instead, add `included_applications: [:mnesia]`, this will also remove the warnings in VSCode. The reason is that you need to firstly create the schema (meaning you create the database), and only then start Mnesia. Thus we have a startup chain:

1. `:mnesia.create_schema` to create a new database.

2. Start Mnesia with `:mnesia.start()`

3. Create the table with `:mnesia.create_table` where you specify the rows and also that you want a disc copy for your node. The parameter `disc_copies: [node()]` means that data is stored both on disc and in the memory.

4. The disc copy directory can be specified in the `config.exs` file (at build time, before compilation and dependencies loading). The directory should be UNIQUE for each node and is created is not exists.

Check:

```bash
iex> :mnesia.system_info()
iex> iex> :mnesia.system_info(:directory)
'.../mndb_test@mycomputer'
iex> :mnesia.table_info(:mcache, :attributes)
[:post_id, :data]
```

In Mnesia, every action needs to be wrapped within a transaction. If something goes wrong with executing a transaction, it will be rolled back and nothing will be saved on the database.

- `:atomic` All operations should occur or no operations should occur in case of an error

## Disc persistance of tables

Tables can be saved both in RAM and on disc. From the Erlang/Mnesia documentation, it is said that "the directory must be unique for each node. Two nodes must never share the same directory".

You can add a node specific name in the "config/confi.exs" file. For example: `config :mnesia, dir: 'mndb_#{Node.self()}'`. If the folder doesn't exist, it will be created.

On the table creation, you should use the `disc_copies` option. The Mnesia documentation explains that "this property specifies a list of Erlang nodes where the table is kept in RAM and on disc. All updates of the table are performed in the actual table and are also logged to disc. If a table is of type disc_copies at a certain node, the entire table is resident in RAM memory and on disc. Each transaction performed on the table is appended to a LOG file and written into the RAM table.

On table creation, add:
`Mnesia.create_table(name, attributes: [...], disc_copies: [Node.self()])`

### Locks

To ensure that there are no race conditions, you can use locks.

- `:write`, which prevents other transactions from acquiring a lock on a resource,

- `:read`, which allows other nodes to obtain only `:read` locks.

If someone has a write lock, no one can acquire either a read lock or a write lock at the same item.

### Distributing Mnesia

- connect nodes

- inform Mnesia that other nodes belong to the cluster:

- ensure that data can be stored on disc

- add the table to the new node

```elixir
def connect_mnesia do
    :mnesia.start()
    :mnesia.change_config(:extra_db_nodes, Node.list())
    :mnesia.change_table_copy_type(:schema, node(), :disc_copies)
    :mnesia.add_table_copy(GameState, node(), :disc_copies)
  end
  ```

- reconfgure Mnesia to share it's contents

## Run the tests

### Inspect a GenServer state

Use `:sys.get_state`  with the GenServer's pid (with `pid = Process.whereis(CachingAnApi.Cache)` or it's name since we named it.

```bash
iex> Process.whereis(CachingAnApi.Cache)
iex> |> :sys.get_state() 
```

```elixir
# to get the arguments of a function, insert
|> IO.inspect(binding())

|> IO.inspect(var, label: "my ctrl point")
```bash

```bash
$ mix run lib/caching_an_api/benchmark.exs
```

Change `@cached` to `true` or `false` to run uncached or cached.

## RESULTS

For 10 endpoints, time: 5, we get:

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

## Enum vs Stream

`Stream` evaluates the functions of the chain for each enumerable, as `Enum` evaluates each enumerable then performs the next function of the chain.

```elixir
iex> [1,2,3]|> Stream.map(&IO.inspect/1) |> Stream.map(&IO.inspect/1) |> Enum.to_list
1,1,2,2,3,3,
iex>  [1,2,3]|> Enum.map(&IO.inspect/1) |> Enum.map(&IO.inspect/1)
1,2,3,1,2,3
```

## PRoduction release

```bash
mix phx.gen.secret
xxxx
export SCRET_KEY_BASE="xxxx"
MIX_ENV=prod mix setup
MIX_ENV=prod mix release
```

### Bakeware

<https://www.youtube.com/watch?v=ML5hQjPQL7A>

<https://github.com/bake-bake-bake/bakeware>
