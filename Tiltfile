##### DNS strategy with headless service
k8s_yaml('./k8-ymls/erl_cookie.yml')

docker_build(
   'rel-myapp',
   context='.',
   dockerfile="./k8-df/Dockerfile.rel.app"
)

# docker_build(
#    'localhost:5005/rel-obs',
#    context='.',
#    dockerfile="./k8-df/Dockerfile.rel.obs"
# )


k8s_yaml(
   [
      './k8-ymls/service-headless.yml',
      # './k8-ymls/service-lb.yml',
      './k8-ymls/myapp-headless.yml',
      # './k8-ymls/observer.yml',
      # './k8-ymls/redis.yml'
   ]
)

# k8s_resource('observer', 
#    resource_deps=['myapp'],
#    trigger_mode=TRIGGER_MODE_MANUAL,
#    auto_init=False
# )
