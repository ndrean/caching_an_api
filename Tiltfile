k8s_yaml('./k8-ymls/ns.yml')

# k8s_resource('erl_cookie', resource_deps=['ns'])
# k8s_resource('sa', resource_deps=['ns'])

k8s_yaml(['./k8-ymls/erl_cookie.yml', './k8-ymls/sa.yml'])

# k8s_yaml('./k8-ymls/registry.yml')


####################################@
docker_build(
   'mix-cluster',
   context='.',
   dockerfile="./k8-df/Dockerfile.mix"
)

docker_build(
   'rel-cluster',
   context='.',
   dockerfile="./k8-df/Dockerfile.rel"
)


k8s_yaml(['./k8-ymls/runner.yml','./k8-ymls/myapp.yml'])

