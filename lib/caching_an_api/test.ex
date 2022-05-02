defmodule CachingAnApi.T do
  def build_array(0), do: [fn x -> x end]
  def build_array(n), do: build_array(n - 1) ++ [fn x -> x ** n end]

  def test3 do
    {t, _res} =
      :timer.tc(fn ->
        build_array(10000)
        |> Task.async_stream(& &1.(2))
        |> Enum.to_list()
      end)

    t
  end

  def test2 do
    {t, _res} =
      :timer.tc(fn ->
        build_array(10000)
        |> Stream.map(& &1.(2))
        |> Enum.to_list()
      end)

    t
  end

  def test1 do
    {t, _res} =
      :timer.tc(fn ->
        build_array(10000)
        |> Enum.map(& &1.(2))
        |> Enum.to_list()
      end)

    t
  end

  def test4 do
    {t, _res} =
      :timer.tc(fn ->
        build_array(10000)
        |> Stream.map(&Task.async(fn -> &1.(2) end))
        |> Stream.map(&Task.await/1)
        |> Enum.to_list()
      end)

    t
  end
end
