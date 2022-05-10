#!/bin/bash

echo "starting cluster.."
host="@127.0.0.1"
for i in a b c
do
    # ttab -w iex --name "$i$host" --cookie :secret -S mix if cookie not set in config.exs
    ttab -w iex --name "$i$host" -S mix
    
    # osascript -e "tell application \"Terminal\" to do script \"iex --sname "$i" -S mix\""
done
echo "done"