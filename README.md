# CachingAnApi

To illustrate the usage of different in-build stores, we cache responses to HTTP calls with different solutions: (a GenServer), an Ets data store and a Mnesia database in the case of a distributed cluster.

> Other unused options here would rely on external databases, such as Redis with PubSub or Postgres with Listen/Notify.

There is a module Api for performing dummy HTTP requests. It calls a Cache module.
We put two options:

- [master]: Cache is just a module that distributes the read/Write to the request data store. Mnesia is a GenServer: with Mnesia system event, it triggers Mnesia cluster startup and update.

- [mnesia-no-gs]: Cache is a GenServer that uses Erlang's node monitoring to triger Mnesia start and cluter update. Then the Mnesia module is just a wrapper.

You can configure which store is used: the state of the Cache GenServer, Ets or Mnesia w/o disc persistance or CRDT. Set the `store: type` with `:mn` or `:ets` or `crdt` or `store: nil` (for the process state). Also set `disc_copy` to `:disc_copy` or `nil` if your want persistance on each node or not.

EtsDb in just a module that wraps Ets, and Mnesia is/or not a supervised GenServer since we want to handle network partition.

## Debbuging

[Nice source](https://staknine.com/debugging-elixir-phoenix/)

## RBAC

[Nice source](https://octopus.com/blog/k8s-rbac-roles-and-bindings)

## The stores

- [ETS](https://www.erlang.org/doc/man/ets.html)
It is an in-build in-memory key-value data store localized in a node and it's life shelf is dependant upon the process that created it. In this case, the app: when we kill all the nodes, this data is lost, which is a wanted feature here.
This data store is **not distributed**: other nodes within a cluster can't access to it.
Data is saved with tuples and there is no need to serialize values.
Since we launch Ets in it's own process, we used the flag `:public`. Any process can thus read and write from the Ets database. The operations have to be made atomic to avoid race conditions (for example, no write and then read within the same function as this could lead to inconsistancies). It then offers shared, concurrent read access to data (meaning scaling upon the number of CPUs used).

A word about [performance between GenServer and Ets](<https://prying.io/technical/2019/09/01/caching-options-in-an-elixir-application.html>).

> Check for the improved [ConCache](https://github.com/sasa1977/con_cache) with TTL support.

- [Mnesia](http://erlang.org/documentation/doc-5.2/pdf/mnesia-4.1.pdf)
Mnesia is an in-build distributed in-memory and optionnally  disc persisted database build (node-based) for concurrency. It works both in memory (**with Ets**) and on disc. As Ets, it stores tuples.
You can define tables whose structure is defined by a record type.
In Mnesia, actions are wrapped within a **transaction**: if something goes wrong with executing a transaction, it will be rolled back and nothing will be saved on the database. This means the operations are `:atomic`,  meaning that all operations should occur or no operations should occur in case of an error. The disc persistance is optional in Mnesia. Set `disc_copy: :disc_copy` or to `nil` in the "config.exs".

  - storage capacity: from the [doc](https://www.erlang.org/faq/mnesia.html), it is indicated that:
    - for ram_copies and disc_copies, the entire table is kept in memory, so data size is limited by available RAM.
    - for disc_copies tables, the entire table needs to be read from disk to memory on node startup, which can take a long time for large table.

> What's the point of using Mnesia? If you need to keep a database that will be used by multiple processes and/or nodes, using Mnesia means you don't have to write your own access controls.
> Furthermore, a [word about scalability performance of Mnesia](http://www.dcs.gla.ac.uk/~amirg/publications/DE-Bench.pdf) and [here](https://stackoverflow.com/questions/5044574/how-scalable-is-distributed-erlang) and [here](https://stackoverflow.com/questions/5044574/how-scalable-is-distributed-erlang).

- [CRDT](https://github.com/derekkraan/delta_crdt_ex)
DeltaCrdt implements a key/value store using concepts from Delta CRDTs. A CRDT can be used as a distributed temporary caching mechanism that is synced across our Cluster. A good introduction to [CRDT](https://moosecode.nl/blog/how_deltacrdt_can_help_write_distributed_elixir_applications).

## The Erlang cluster

In an Erlang cluster, all nodes are fully connected, with N(N-1)/2 <=> O(N^2) TCP/IP connections.
A [word](http://dcs.gla.ac.uk/~natalia/sd-erlang-improving-jpdc-16.pdf) on full P2P Erlang clusters. The performance plateau at 40 nodes and do not scale beyond 60 nodes.

To create a cluster, from an **IEX** session, you need to pass a name to connect the nodes and pass the same cookie to each node.

### Launch the nodes

- [name] Use the flag `--sname` (for short name, within the *same* network) and it will assign **:"a@your-local-system-name"**. If you are not running in the same network, use instead the flag `--name` with a qualified domain, such as **:"a@127.0.0.1"** or **:"a@example.com"**.

```elixir
# term 1
> iex --sname a --cookie :my_secret -S mix
iex(a@MacBookND)>
# or
> iex --name A@127.0.0.1  --cookie :my_secret -S  mix
iex(A@127.0.0.1)>
```

So to launch 3 nodes, run in 3 separate terminals:

```elixir
#t1
> iex --name A@127.0.0.1  --cookie :my_secret -S  mix
#t2
> iex --name A@127.0.0.1  --cookie :my_secret -S  mix
#t3
> iex --name A@127.0.0.1  --cookie :my_secret -S  mix
```

#### Automatic launch of IEX sessions in new terminals

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

### Connect the nodes

- [connect] Thanks to the **transitivty** of the BEAM connections,  you just need to connect one node to the N-1 others to get the full P2P network of N(N-1)/2 TPC connections.

#### Manual connection

Within one terminal, say t1, run:

```elixir
iex(A@127.0.0.1)> for l <- ["A","B","C"], do: String.to_atom(l<> "@127.0.0.1") |> Node.connect()
[true,true,true,true ]

# check with:
iex(A@127.0.0.1)> :net.ping(:"C@127.0.0.1")
:pong 
iex(B@127.0.0.1)> :net.ping(:"D@127.0.0.1")
:pong 
```

With **code**, if you want to connect two machines "a@node" and "b@node" with respective IP of 192.168.0.1 and 192.168.0.2, then you would do:

```elixir
# on the "a@node@ machine
Node.start :"a@192.168.0.1"
Node.set_cookie :my_secret
Node.connect "b@192.168.0.2"

# on the "b@node" machine
Node.start :"b@192.168.0.2"
Node.set_cookie :my_secret

# from A@node:
Node.connect(:"b@192.168.0.1")
Node.list()
[:"b@192.168.0.1"]
#from b@node
Node.list()
[:"a@192.168.0.1"]
```

To disconnect a node from another, run:

```elixir
iex(:a@127.0.0.1)> Node.disconnect(:"b@127.0.0.1")
```

[TODO] With the compiled code:

```bash
# file vm.args contains name and cookie
./bin/...
```

#### Automatic Cluster connection: `libcluster`

For the automatic clusterisation, you can use use `libcluster` in `epmd` mode (IP based) or `gossip` mode (DNS based).

> With the `epmd` mode, you need to pass a first host as a config. To be tested between different domains, not only localhost ??

With the `epmd` mode, you can `b@node> Node.disconnect(A)` from another node B and need to manually reconnect with `a@node> Node.connect(B)`, both A and B will restart since Mnesia detects a partition, and this is captured here to restart the node with a fresh table. With the `gossip` mode, an attempt to disconnect will trigger a fresh restart on the caller and calling nodes.

- set the `gossip` topology for automatic DNS. The setting are in "config/config.exs".
- use `:net_kernel.monitor_nodes(true)`in `GenServer.start_link` to discover the nodes

### Remote-Procedure-Call between nodes

> see OPT25 with module `peer`

You can execute a function on a reomte node. You can use `:rpc.call` or `GenServer.call` from a remote node (if you call a function within a GenServer)

If you have:

```elixir
iex(:a@127.0.0.1)> EtsDb.get(1)
"a"
iex(:b@127.0.0.1)> EtsDb.get(1)
"b"
```

then you see:

```elixir
iex(:a@127.0.0.1)> :rpc.call(:"b@127.0.0.1", EtsDb, :get, [1] )
"a"
iex(:c@127.0.0.1)> for node <- Node.list(), do: {node, :rpc.call(node, EtsDb, :get, [1])}
["a@127.0.0.1": "a", "b@127.0.0.1": "b"]
```

Suppose we have a client function `Module.nodes` implemented with a callback `:nodes` within a GenServer, then you can use `GenServer.call` to run a remote function on another node (be careful with the construction of the functions with the brackets "}").

```elixir
iex(c@127.0.0.1)> GenServer.call({MnDb, :"b@127.0.0.1"}, {:node_list})
[:"a@127.0.0.1", :"c@127.0.0.1"]

iex(c@127.0.0.1)> for node <- Node.list(), do: {node, GenServer.call({MnDb, node}, {:nodes}) }
[
  "a@127.0.0.1": [:"b@127.0.0.1", :"c@127.0.0.1"],
  "b@127.0.0.1": [:"a@127.0.0.1", :"c@127.0.0.1"]
]

# or use `multicall`-> {sucess, failure}
iex(:c@127.0.0.1)> :rpc.multicall(EtsDb, :get, [1])
{["a@127.0.0.1": "a", "b@127.0.0.1": "b"], []}
```

## Ets

Some documents about the data store: [Elixir-lang-org: Ets](https://elixir-lang.org/getting-started/mix-otp/ets.html), and [Elixir school: Ets](https://elixirschool.com/en/lessons/storage/ets) and an excellent article talking about [Ets in production](https://sayan.xyz/posts/elixir-erlang-and-ets-alchemy).

Some useful commands:

- creation: just use `:ets.new`
- read/write: `:ets.lookup` and `:ets.insert` to respectively "get" and "put"
- read all data of the table ":ecache": `:ets.tab2list(:ecache)`

To check that the EtsDb GenServer module is supervised

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

## Mnesia

### Documentation / Sources

The [Mnesia](http://erlang.org/documentation/doc-5.2/pdf/mnesia-4.1.pdf) documentation and the [Elixir school lesson](https://elixirschool.com/en/lessons/storage/mnesia). Also [LearnYouSomeErlang](https://learnyousomeerlang.com/mnesia#whats-mnesia).

Usefull libraries:

- [library Mnesiac](https://github.com/beardedeagle/mnesiac/blob/master/lib/mnesiac/store_manager.ex)
- [Library Amensia](https://github.com/meh/amnesia)

Other [nice source](https://mbuffa.github.io/tips/20201111-elixir-troubleshooting-mnesia/) or [here](https://www.welcometothejungle.com/fr/articles/redis-mnesia-distributed-database) and a bit about [amensia](https://code.tutsplus.com/articles/store-everything-with-elixir-and-mnesia--cms-29821).

### Configuration

All you need is to give **names** to tables and a **folder location** for each node for the disc copies.

> the documentation says that "the directory must be UNIQUE for each node. "Two nodes must never share the same directory".

You can add a node specific name in the "config/confi.exs" file. For example: `config :mnesia, dir: 'mndb_#{Node.self()}'`. The "config/config.exs" is used at **build time**, before compilation and dependencies loading).
If the folder doesn't exist, it will be created.

Mnesia can be started in code with `:mnesia.start()`. We can add `:mnesia` in the MixProject application `included_application` to remove the VSCode warnings. Not adding it in `extra_application` is mandatory in single node mode since we need to create the schema before starting Mnesia.

### Mnesia system event handler

We use the Mnesia system event handler by declaring `:mnesia.subscribe(:system)`. We have a `handle_info` call in the Cache module to log the message.

### Single node mode startup

> DONT add `:mnesia` in the MixProject application `:extra_applications` since you will need to start it manually. Instead, add `included_applications: [:mnesia]`. This will also remove the warnings in VSCode. The reason is that you need to firstly create the schema (meaning you create the database), and only then start Mnesia.

The sequence is:  `:mnesia.create_schema` to create a new database, then  `:mnesia.start()`, then `:mnesia.create_table` where you specify the rows and also that you want a disc copy for your node. The parameter `disc_copies: [node()]` means that data is stored both on disc and in the memory. Finally, the disc copy directory can be specified in the `config.exs` file.

### Distributed Mnesia startup

The sequence is:

- start Mnesia. Two options: declare `[extra_applications: [:mnesia]` in MixProject  or use `:mnesia.start()`.
- connect nodes and inform Mnesia that other nodes belong to the cluster,
- ensure that data (schema and table) are stored on disc. Two copy functions are used, depending if it's the schema or table.

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

You can run `:ets.tab2list(:mcache)` in a node and this displays the whole Mnesia table which is in RAM.

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

## Kubernetes notes

> Watch:
`kubectl get events --watch`
> Scaling deployments:

```bash
kubectl scale deploy myapp --replicas=3
```

> Attach to a running pod (here, a release that runs with `start_iex`):

```bash
kubectl attach myapp-89b6ddf5-kjmw4 -i
iex(myapp@10.42.0.116)2>
```

or

```bash
kubectl exec -it runner--89b6ddf5-kjmw4 -- sh
bash# iex --cookie "$(echo $ERLANG_COOKIE)" --name "$(echo $APP_NAME)@$(echo $POD_IP))" -S mix
iex(myapp@10.42.0.116)2>
```

```bash
> kubectl exec -it myapp-d59cc7b8f-hhwpc -- sh

bash$ nslookup myapp-svc-headless.stage.svc.cluster.local

Server:  10.96.0.10
Address: 10.96.0.10:53
Name: myapp-svc-headless.stage.svc.cluster.local
Address: 10.244.0.54
Name: myapp-svc-headless.stage.svc.cluster.local
Address: 10.244.0.53 
````

> Create cluster with local registry

```bash
> ctlptl apply -f k3d-cluster-reg.yml
> ctlptl delete registry k3d-reg
> ctlptl delete -f k3d-cluster-reg.yml
```

> Use namespace

Do not forget to create and assing a namespace to the project:

```bash
kubectl create ns stage
kubens stage
```

> Cleaning local images in the local registry:

```bash
docker rmi $(docker images |grep 'localhost*')
```

## k8 DNS

In a Kubernetes cluster, service acts as a Service Discovery mechanism. When deploying a service, a DNS name is assigned to it. These DNS names can be used to communicate with the services and the upstream backing pods.

Kubernetes DNS service named as kube-dns, which has a static IP. This address of name-server is stored under /etc/resolv.conf on each pod and generally it should pickup from host /etc/resolv.conf. DNS naming rules resolve pod and service DNS to their corresponding cluster IPs. Kubernetes DNS support forward lookup (A records), port lookup (SRV records) and some other options.

When deploying regular service resource K8s allocates IP address (cluster Ip) for it. This is being used as an the single entry point for pods backed by the service,which enables it to act as a proxy for upstream pods. And also regular services are assigned a DNS A record which resolves to the cluster IP of the service. And also DNS SRV Records are created for named ports of the service which resolves to the port number and the domain name.

In case of headless service K8s does not allocate any IP address for it. Headless services are also assigned a DNS A record which resolves to a set of IPs corresponds to back-end pods managed by the service, which allows interact directly with the pods instead of proxy. And also when deploying of headless service, K8s will still create the DNS A records for individual upstream pods which enables to resolve headless service domain name to IP addresses of connected pods. Additionally DNS SRV records are also created for headless services, which resolves to set of upstream pod FQDNs (i.e. domain name of the pod of the form `<pod name>.<service name>.<namespace>.<cluster base DNS>`).

In regular deployments, pod names will be randomly generated and pod FQDNs are derived from its IP address and service name. I.e. `A-B-C-D.<service name>.<namespace>.<cluster base DNS>` where A-B-C-D is the IP address with ‘.’ converted to ‘-’.

Pod FQDN in headless services DNS SRV records are also in this pod FQDN form for each deployment type. Therefore host.domain part of the Erlang node name required to be in this form (i.e. pod FQDN) as DNS SRV query for front-ended headless-service is used to discover upstream pods.

### Get `observer` working remotely

Set up the `Observer` for remotely connecting to the mix release deployed Elixir app.

For Docker, [follow this](https://github.com/chazsconi/connect-remote-elixir-docker)

From a terminal, do:

1. In `MixProjects`, set:

```elixir
defp releases do
  [
    myapp: [
      include_executables_for: [:unix],
      applications: [
        caching_an_api: :permanent,
        runtime_tools: :permanent
      ]
    ]
  ]
  end
```

2. Run `mix.release` (or rerun `tilt up` to compile the release dockerfile).

To launch remotely the observer, do:

- Run with a batch file

  ```bash
  ./erl-observer.sh -l app=myapp -c release_secret
  ```

- Manual

1. Get the PORT:

```bash
kubectl exec -it myapp-6dd7f6b998-r8kwp -- sh -c "./erts-12.2.1/bin/epmd -names | tail -n 1"
~$ name theapp at port 39391
```

2. In one terminal, set PORT and run the port-forward:

```bash
PORT=39391

kubectl port-forward  <choose-the-pod: myapp-6dd7f6b998-r8kwp> 4369 39391
#or
ssh -N -L PORT:localhost:PORT -L 4369:localhost:4369 -i ~/.minikube/machines/minikube/id_rsa docker@$(minikube ip)
```

3. In another terminal, run the following to get the `observer` running.

```bash
> erl -name myapp@127.0.0.1 -run observer
Erlang/OTP 24 [erts-12.3.2] ... [dtrace]
Eshell V12.3.2  (abort with ^G)
(myapp@127.0.0.1)1>
```

### Checking

In another terminal, attach to a pod:

```bash
kubectl attach -i 
iex(theapp@10.244.0.15)1> Api.Stream_synced(1..10)
[...]
iex(theapp@10.244.0.15)2> :rpc.call(:"theapp@10.244.0.16", Mndb, :data, [])
[...]
```

In another terminal, change the number of running pods:

```bash
kubectl scale deploy myapp --replicas=6
```

Check that the data is transfered and Mnesia is running on all pods.

```bash
iex(theapp@10.244.0.15)3> :rpc.call(:"theapp@10.244.0.20", Mndb, :data, [])
[...]

iex(theapp@10.244.0.15)4> :mnesia.system_info(:running_db_nodes)
[:"theapp@10.244.0.15", :...,:"theapp@10.244.0.22"]
```

## Actor model vs Object-Orientated

**Objects** enscapsulate state and interact with **functions**. **Encapsulation** dictates that the internal data of an object is not accessible directly from the outside; it can only be modified by invoking a set of curated methods. The object is responsible for exposing safe operations that protect the invariant nature of its encapsulated data. Since functions are executed with threads, and since encapsulation only guarantee for single-threaded access, you need to add mechanisms such as **locks**.

**Actors** interact with **message** passing. They have their own state, the **behavior**, a function that defines how to react to messages.
Instead of calling methods like objects do, actors *receive* and *send* messages to each other. Sending a message does not transfer the thread of execution from the sender to the destination. An actor can send a message and continue without blocking. Message-passing in actor systems is fundamentally **asynchronous**, i.e. message transmission and reception do not have to happen at the same time, and senders may transmit messages before receivers are ready to accept them. Messages go into actor  **mailboxes**. Actors execute independently from the senders of a message, and they react to incoming messages sequentially, one at a time. While each actor processes messages sent to it sequentially, different actors work concurrently with each other so that an actor system can process as many messages simultaneously as the hardware will support.

An important difference between passing messages and calling methods is that messages have no return value. By sending a message, an actor delegates work to another actor.
**Actors** react to messages just like **objects** react to methods invoked on them.


### Elixir notes

[handle_continue](https://elixirschool.com/blog/til-genserver-handle-continue/)

[GernServer stop](https://alexcastano.com/how-to-stop-a-genserver-in-elixir/)

[Handling events](https://mkaszubowski.com/2021/01/09/elixir-event-handling.html)

#### Production release

Take a look at [Render](https://render.com/docs/deploy-elixir-cluster) and [Gigalixir](https://gigalixir.com/#/about) and [fly.io](https://fly.io/docs/getting-started/elixir/)

#### Bakeware

<https://www.youtube.com/watch?v=ML5hQjPQL7A>

<https://github.com/bake-bake-bake/bakeware>

#### Enum vs Stream

`Stream` evaluates the functions of the chain for each enumerable, whereas `Enum` evaluates each enumerable then performs the next function of the chain.

```elixir
iex> [1,2,3]|> Stream.map(&IO.inspect/1) |> Stream.map(&IO.inspect/1) |> Enum.to_list
1,1,2,2,3,3,
iex>  [1,2,3]|> Enum.map(&IO.inspect/1) |> Enum.map(&IO.inspect/1)
1,2,3,1,2,3
```

### Erlang without EPMD

[Application Github](https://github.com/tsloughter/epmdless)

[Source 1](https://medium.com/hackernoon/running-distributed-erlang-elixir-applications-on-docker-b211d95affbe)

[source](https://www.erlang-solutions.com/blog/erlang-and-elixir-distribution-without-epmd/)

```elixir
# A module containing the function that determines the port number based on a node name

defmodule Epmdless do
  def dist_port(name) when is_atom(name) do
    dist_port Atom.to_string name
  end

  def dist_port(name) when is_list(name) do
    dist_port List.to_string name
  end

  def dist_port(name) when is_binary(name) do
    # Figure out the base port.  If not specified using the `inet_dist_base_port` kernel environment variable, default to 4370, one above the epmd port.
    base_port = :application.get_env :kernel, :inet_dist_base_port, 4370

    # Now, figure out our "offset" on top of the base port. The offset is the integer just to the left of the @ sign in our node name. If there is no such number, the offset is 0. Also handle the case when no hostname was specified.
    node_name = Regex.replace ~r/@.*$/, name, ""
    offset =
      case Regex.run ~r/[0-9]+$/, node_name do
    nil -&gt;
      0
    [offset_as_string] -&gt;
      String.to_integer offset_as_string
      end

    base_port + offset
  end
end

defmodule Epmdless_dist do

  def listen(name) do
    # Here we figure out what port we want to listen on.

    port = Epmdless.dist_port name

    # Set both "min" and "max" variables, to force the port number to this one.
    :ok = :application.set_env :kernel, :inet_dist_listen_min, port
    :ok = :application.set_env :kernel, :inet_dist_listen_max, port

    # Finally run the real function!
    :inet_tcp_dist.listen name
  end

  def select(node) do
    :inet_tcp_dist.select node
  end

  def accept(listen) do
    :inet_tcp_dist.accept listen
  end

  def accept_connection(accept_pid, socket, my_node, allowed, setup_time) do
    :inet_tcp_dist.accept_connection accept_pid, socket, my_node, allowed, setup_time
  end

  def setup(node, type, my_node, long_or_short_names, setup_time) do
    :inet_tcp_dist.setup node, type, my_node, long_or_short_names, setup_time
  end

  def close(listen) do
    :inet_tcp_dist.close listen
  end

  def childspecs do
    :inet_tcp_dist.childspecs
  end
end

defmodule Epmdless_epmd_client do
# erl_distribution wants us to start a worker process.  We don't need one though

  def start_link do
    :ignore
  end

# As of Erlang/OTP 19.1, register_node/3 is used instead of register_node/2, passing along the address family, `inet_tcp` or `inet6_tcp`.  This makes no difference for our purposes

  def register_node(name, port, _family) do
    register_node(name, port)
  end

  def register_node(_name,_port) do
    # This is where we would connect to epmd and tell it which port we're listening on, but since we're epmd-less, we don't do that.

    # Need to return a "creation" number between 1 and 3.
    creation = :rand.uniform 3
    {:ok, creation}
  end

  def port_please(name, _ip) do
    port = Epmdless.dist_port name
    # The distribution protocol version number has been 5 ever since Erlang/OTP R6.
    version = 5
    {:port, port, version}
  end

  def names(_hostname) do
    # Since we don't have epmd, we don't really know what other nodes there are.
    {:error, :address}
  end
end
```

```bash
iex --erl "-proto_dist Elixir.Epmdless -start_epmd false -epmd_module Elixir.Epmdless_epmd_client" --sname foo3
```
