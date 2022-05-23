defmodule Orders do
  @event_consumers [
    {Inventory, :handle_event},
    {Delivery, :handle_event},
  ]

  def create_order(attrs) do
    {:ok, order} = save_order(attrs)

    event = %Orders.Event{type: :new_order, payload: order}
    @event_consumers
    |> Enum.each(fn {module, func} ->
      apply(module, func, [event])
    end)

    {:ok, order}
  end
end
