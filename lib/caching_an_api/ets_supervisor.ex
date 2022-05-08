# defmodule Ets.Supervisor do
#   use Supervisor
#   require Logger

#   def start_link(name) do
#     Supervisor.start_link(__MODULE__, name, name: __MODULE__)
#   end

#   @impl true
#   def init(name) do
#     Supervisor.init(
#       [
#         {EtsDb, name}
#       ],
#       strategy: :one_for_one
#     )
#   end
# end
