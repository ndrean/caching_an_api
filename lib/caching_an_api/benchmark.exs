Benchee.run(
  %{
    # "test1" => fn ->
    #   CachingAnApi.T.test1()
    # end,
    # "test2" => fn ->
    #   CachingAnApi.T.test2()
    # end,
    # "test3" => fn ->
    #   CachingAnApi.T.test3()
    # end,
    # "test4" => fn ->
    #   CachingAnApi.T.test4()
    # end
    "yield_many_asynced_stream" => fn ->
      CachingAnApi.Api.yield_many_asynced_stream()
    end,
    "asynced_stream" => fn ->
      CachingAnApi.Api.asynced_stream()
    end,
    "enum_yield_many" => fn ->
      CachingAnApi.Api.enum_yield_many()
    end,
    "stream_synced" => fn ->
      CachingAnApi.Api.stream_synced()
    end
  },
  time: 10
)
