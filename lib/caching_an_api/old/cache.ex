# defmodule Cache do
#   require Logger

#   def get(key, opts \\ []) do
#     case opts[:store] do
#       :mn ->
#         MnDb.read(key, opts[:mn_table])

#       :ets ->
#         EtsDb.get(key, opts[:ets_table])

#       :dcrdt ->
#         nil
#     end
#   end

#   def put(key, data, opts) do
#     case opts[:store] do
#       :mn ->
#         MnDb.write(key, data, opts[:mn_table])

#       :ets ->
#         EtsDb.put(key, data, opts[:ets_table])

#       :dcrt ->
#         nil
#     end
#   end

#   def inverse(index, key, opts) do
#     MnDb.inverse(index, key, opts[:mn_table])
#   end
# end
