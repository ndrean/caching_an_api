defmodule Api do
  alias Cache
  @url "https://jsonplaceholder.typicode.com/todos/"
  # @range 20..30
  # @cache true

  def fetch(i, f) do
    data = Cache.get(i)

    case data do
      nil ->
        f.(i)

      %{"was_cached" => bool} ->
        fetch_or_update_cache(bool, i, data)
    end
  end

  def fetch_or_update_cache(bool, i, data) do
    case bool do
      true ->
        {:ok, {i, %{response: data}}}

      false ->
        Cache.put(i, %{data | "was_cached" => true})
        {:ok, {i, %{response: Cache.get(i)}}}
    end
  end

  # 1-nocache #2-cached
  def enum_yield_many(range) do
    range
    |> Enum.map(fn i ->
      Task.async(fn -> fetch(i, &sync/1) end)
    end)
    |> Task.yield_many()
    |> Enum.map(fn {_status, res} -> res end)
  end

  # 2-nocache #4-cached
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

  # 3-nocache #1-cached
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

        Cache.put(i, body)
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

        Cache.put(i, body)
        {i, %{response: body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        reason
    end
  end

  defp get_page(i), do: @url <> to_string(i)
end
