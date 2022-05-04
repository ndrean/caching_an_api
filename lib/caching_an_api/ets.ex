defmodule EtsDb do
  @moduledoc """
  This module contains the setup of an Ets table. It is used by the Cache module.
  """

  @doc """
  The Ets store is instanciated here.
  """
  def setup(table_name) do
    :ets.new(
      table_name,
      [:ordered_set, :public, :named_table, read_concurrency: true, write_concurrency: true]
    )
  end
end
