#!/bin/bash
# This script provides easy way to debug remote Erlang nodes that is running in a kubernetes cluster.
# Usage: ./erl-observe.sh -l app=my_all -n default -c erlang_cookie
#
# Don't forget to include `:runtime_tools` in your mix.exs application dependencies.
set -e

# Trap exit so we can try to kill proxies that has stuck in background
function cleanup {
  echo " - Stopping kubectl proxy."
  kill $! &> /dev/null
}
trap cleanup EXIT

# Read configuration from CLI
while getopts "n:l:u:c:" opt; do
  case "$opt" in
    n)  K8S_NAMESPACE="--namespace=${OPTARG}"
        ;;
    l)  K8S_SELECTOR=${OPTARG}
        ;;
    u)  ERL_USER=${OPTARG}
        ;;
    c)  ERL_COOKIE=${OPTARG}
        ;;
  esac
done

# Required part of config
if [ ! $K8S_SELECTOR ]; then
  echo "[E] You need to specify Kubernetes selector with '-l' option."
  exit 1
fi

echo " - Selecting pod with '-l ${K8S_SELECTOR} ${K8S_NAMESPACE:-default}' selector."
POD_NAME=$(kubectl get pods -l ${K8S_SELECTOR} ${K8S_NAMESPACE} -o jsonpath='{.items[0].metadata.name}')

echo " - Resolving Erlang node port on a pod '${POD_NAME}'."
EPMD_OUTPUT=$(echo ${POD_NAME} | xargs -o -I my_pod kubectl exec my_pod ${K8S_NAMESPACE} -i -t -- ./erts-12.2.1/bin/epmd -names | tail -n 1)

echo " - Got output from epmd: "
echo " - ${EPMD_OUTPUT}"
eval 'EPMD_OUTPUT=($EPMD_OUTPUT)'

# By default, cookie is the same as node name
if [ ! $ERL_COOKIE ]; then
  ERL_COOKIE=${EPMD_OUTPUT[1]}
fi

echo " Cookie: '${ERL_COOKIE}'"
# By default, user is debug
if [ ! $ERL_USER ]; then
  ERL_USER="debug"
fi

# Strip newlines from last element of output
OTP_PORT=${EPMD_OUTPUT[4]//[$'\t\r\n ']}

echo " - Connecting on port ${OTP_PORT} as user '${ERL_USER}' with cookie '${ERL_COOKIE}'."

# Kill epmd on local node to free 4369 port
killall epmd || true

# Replace it with remote nodes epmd and proxy remove erlang app port
echo "kubectl port-forward ${POD_NAME} ${K8S_NAMESPACE} 4369 ${OTP_PORT}"

kubectl port-forward $POD_NAME $K8S_NAMESPACE 4369 $OTP_PORT &> /dev/null &
sleep 1

iex --erl "-proto_dist inet6_tcp" --sname ${ERL_USER} --cookie ${ERL_COOKIE} -e "IO.inspect(Node.connect(:'${ERL_USER}@10.244.0.196'), label: \"Node Connected?\"); IO.inspect(Node.list(), label: \"Connected Nodes\"); :observer.start"
# Run observer in hidden mode to don't heart clusters health
# erl -name $ERL_USER@127.0.0.1 -setcookie $ERL_COOKIE -hidden -run observer