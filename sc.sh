#!/bin/bash

echo "starting cluster.."
host="@127.0.0.1"
for i in a b
do
    ttab -w iex --name "$i$host" -S mix
    
    # osascript -e "tell application \"Terminal\" to do script \"iex --sname "$i" -S mix\""
done
echo "done"