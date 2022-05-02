defmodule CachingAnApiTest do
  use ExUnit.Case
  doctest CachingAnApi

  test "greets the world" do
    assert CachingAnApi.hello() == :world
  end
end
