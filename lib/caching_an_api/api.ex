defmodule Api do
  require Logger

  @url "https://jsonplaceholder.typicode.com/todos/"

  @opts %{
    store: Application.get_env(:caching_an_api, :store) || :ets,
    mn_table: Application.get_env(:caching_an_api, :mn_table) || :mcache,
    ets_table: Application.get_env(:caching_an_api, :ets_table) || :ecache
  }

  # Api.stream_synced(1..2)

  def fetch(i, f) do
    data = Cache.get(i, @opts)

    case(data) do
      nil ->
        f.(i)

      %{"was_cached" => b1, "completed" => b2} ->
        case @opts.store do
          :mn ->
            if !b1 && !b2 do
              data = Cache.inverse(i, "completed", @opts)
              fetch_or_update_cache(data["was_cached"], i, data)
            else
              fetch_or_update_cache(data["was_cached"], i, data)
            end

          :ets ->
            fetch_or_update_cache(data["was_cached"], i, data)
        end
    end
  end

  def fetch_or_update_cache(bool, i, data) do
    case bool do
      true ->
        {:ok, {i, %{response: data}}}

      false ->
        new_data = Map.put(data, "was_cached", true)
        Cache.put(i, new_data, @opts)
        {:ok, {i, %{response: new_data}}}
    end
  end

  # 2
  def enum_yield_many(range) do
    range
    |> Enum.map(fn i ->
      Task.async(fn -> fetch(i, &sync/1) end)
    end)
    |> Task.yield_many()
    |> Enum.map(fn {_status, res} -> res end)
  end

  # 4
  def asynced_stream(range) do
    range
    |> Task.async_stream(fn i -> fetch(i, &sync/1) end)
    |> Enum.map(fn {_status, res} -> res end)
  end

  # 4-nocache #4-cached
  # yield_many sends a tuple {task, result}
  def yield_many_asynced_stream(range) do
    range
    |> Stream.map(fn i ->
      Task.async(fn -> fetch(i, &sync/1) end)
    end)
    |> Stream.map(&Task.yield(&1))
    |> Enum.map(fn {_task, res} -> res end)
  end

  # 1
  def stream_synced(range) do
    range
    |> Stream.map(fn i -> fetch(i, &async/1) end)
    |> Enum.map(fn {_status, res} -> res end)
  end

  def async(i) do
    task = Task.async(fn -> HTTPoison.get(get_page(i)) end)

    case Task.yield(task) do
      {:ok, {:ok, %HTTPoison.Response{status_code: 200, body: body}}} ->
        body =
          body
          |> Poison.decode!()
          |> Map.put("was_cached", false)

        Cache.put(i, body, @opts)
        {:ok, {i, %{response: body}}}

      {:ok, {:error, %HTTPoison.Error{reason: reason}}} ->
        {:error, reason}
    end
  end

  def sync(i) do
    url = get_page(i)

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body =
          body
          |> Poison.decode!()
          |> Map.put("was_cached", false)

        Cache.put(i, body, @opts)
        {i, %{response: body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        reason
    end
  end

  defp get_page(i), do: @url <> to_string(i)
end
