# proxmox_inventory

## Table of Contents

1. [Description](#description)
1. [Requirements](#requirements)
1. [Usage](#usage)
1. [Examples](#examples)

## Description

This module includes a [Bolt] plugin to generate targets from [Proxmox VE].

## Requirements

This Bolt plugin requires the [proxmox-api] gem to connect to the [Proxmox
REST API]. _If it is not installed, the plugin will automatically attempt to
when the plugin is executed by Bolt._

You will need a `token` and `secret`, or `username`, `password` and `realm` to
authenticate.

## Usage

The Proxmox inventory plugin supports looking up running LXC and QEMU VMs.
It supports several configuration properties.

* `username`: _Do not set if using a token_
* `password`: _Do not set if using a token_
* `realm`: _Do not set if using a token_
* `token`: Complete API token (eg. admin@pve!puppetbolt)
* `secret`: Token secret
* `host`: Hostname of the Proxmox node (any cluster member)
* `port`: API port (optional)
* `verify_ssl`: Set to false if using a self-signed certificate
* `type`: Filter on VM type, *qemu* or *lxc* (optional, default 'all')
* `target_mapping`: A hash of the target attributes to populate with resource
  values. Proxmox *cluster/resources* and *node configuration* attributes are
  available for mapping. Network interface (eg. net0, net1, ...) string value
  is converted to a Hash.
  Default mapping:
      name: fqdn
      alias: name
      uri: net0.ip

## Examples

```
groups:
  - name: lxc proxmox containers at dc1
    targets:
      - _plugin: proxmox_inventory
        host: dc1.bogus.site
        username: admin
        password: supersecret
        realm: pve
        type: lxc
        target_mapping:
          name: fqdn
          uri: net0.ip
          alias: name
          vars:
            arch: arch
            type: type
  - name: all proxmox VMs at dc2
    targets:
      - _plugin: proxmox_inventory
        host: dc2.another.site
        token: admin@pve!bolt
        secret: 095ce810-4e28-11ed-bdc3-0242ac120002
        target_mapping:
          alias: vmid
```

> **Qemu**: the agent service must be running on the VM to determine the IP address

[proxmox-api]: https://rubygems.org/gems/proxmox-api/
[Proxmox REST API]: https://pve.proxmox.com/pve-docs/api-viewer/
[Bolt]: https://puppet.com/docs/bolt/latest/bolt.html
[Proxmox VE]: https://www.proxmox.com/en/proxmox-ve
[patch]: https://github.com/L-Eugene/proxmox-api/pull/1
