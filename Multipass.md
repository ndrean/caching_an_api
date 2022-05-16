# Mulitpass

[Source](https://ubuntu.com/blog/replacing-docker-desktop-on-windows-and-mac-with-multipass)

```bash
multipass launch --cloud-init - --disk 40G --mem 4G --cpus 4 --name docker-vm <<EOF
groups:
- docker
snap:
  commands:
  - [install, docker]
runcmd:
- adduser ubuntu docker
EOF
```
