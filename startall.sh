#! /bin/bash

osascript -e 'tell application "Terminal" to do script "iex --sname a -S mix"' \
&& osascript -e 'tell application "Terminal" to do script "iex --sname b -S mix"' \
&& osascript -e 'tell application "Terminal" to do script "iex --sname c -S mix"' \
&& osascript -e 'tell application "Terminal" to do script "iex --sname d -S mix"'
