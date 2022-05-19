###### Kubernetes (IP) strategy with service-account: uses the Kubernetes Metadata API to query nodes based on a label selector and basename

k8s_yaml(['./k8-ymls/erl_cookie.yml', './k8-ymls/svc-account.yml'])

docker_build(
   'rel-cluster',
   context='.',
   dockerfile="./k8-df/Dockerfile.rel"
)

k8s_yaml('./k8-ymls/myapp.yml')


# allow_k8s_contexts('k3d-k3s-default')
