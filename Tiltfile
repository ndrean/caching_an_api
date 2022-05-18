##### DNS strategy with headless service
k8s_yaml('./k8-ymls/erl_cookie.yml')
docker_build(
   'rel-cluster',
   context='.',
   dockerfile="./k8-df/Dockerfile.rel"
)

# docker_build(
#    'mix-cluster',
#    context='.',
#    dockerfile="./k8-df/Dockerfile.mix"
# )

k8s_yaml(
   [
      './k8-ymls/service-headless.yml',
      './k8-ymls/myapp-headless.yml',
      # './k8-ymls/runner-headless.yml',
      './k8-ymls/redis.yml'
      
   ]
)

allow_k8s_contexts('minikube')
# k8s_resource(workload='myapp', port_forwards=4369)

###### Kubernetes strategy with service-account: uses the Kubernetes Metadata API to query nodes based on a label selector and basename

# k8s_yaml(['./k8-ymls/erl_cookie.yml', './k8-ymls/sa.yml'])
# docker_build(
#    'rel-cluster',
#    context='.',
#    dockerfile="./k8-df/Dockerfile.rel"
# )
# docker_build(
#    'mix-cluster',
#    context='.',
#    dockerfile="./k8-df/Dockerfile.mix"
# )
# k8s_yaml(['./k8-ymls/runner.yml','./k8-ymls/myapp.yml'])



