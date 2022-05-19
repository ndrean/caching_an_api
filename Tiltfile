##### DNS strategy with headless service
k8s_yaml('./k8-ymls/erl_cookie.yml')

docker_build(
   'rel-cluster',
   context='.',
   dockerfile="./k8-df/Dockerfile.rel"
)

k8s_yaml(
   [
      './k8-ymls/service-headless.yml',
      './k8-ymls/myapp-headless.yml',
      './k8-ymls/redis.yml'
   ]
)
