defmodule Essai do
  import Cache

  def trial do
    get(1)
    |> inspect()

    :ets.lookup(:ecache, 1)
    |> inspect()
  end
end
