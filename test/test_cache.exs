defmodule TestCache do
  use ExUnit.Case

  test "check connection" do
    Api.fetch(1, &Api.sync/1)
    %{"id" => val} = Cache.get(1)
    assert val == 1
  end

  test "check cache" do
    Api.fetch(1, &Api.sync/1)
    Api.fetch(1, &Api.sync/1)
    %{"was_cached" => val} = Cache.get(1)
    assert val == true
  end
end
