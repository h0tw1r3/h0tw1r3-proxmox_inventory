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
* `type`: Either *qemu* or *lxc* (required)
* `target_mapping`: A hash of the target attributes to populate with resource
  values. Proxmox *cluster/resources* and *node configuration* attributes are
  available for mapping. Network interfaces (eg. net0, net1, ...) are
  indexed under the *net* Array[], and the value is mapped to a Hash.

## Examples

```
groups:
  - name: proxmox
    targets:
      - _plugin: proxmox_inventory
        host: pve.bogus.site
        username: admin
        password: supersecret
        realm: pve
        type: lxc
        target_mapping:
          name: fqdn
          uri: net.0.ip
          alias: hostname
          vars:
            arch: arch
            type: type
      - _plugin: proxmox_inventory
        host: pve.bogus.site
        token: admin@pve!bolt
        secret: 095ce810-4e28-11ed-bdc3-0242ac120002
        type: qemu
        target_mapping:
          name: fqdn
          uri: agent.net.0.ip
          alias: name
```

> **Qemu**: the agent service must be running on the VM to determine the IP address

[proxmox-api]: https://rubygems.org/gems/proxmox-api/
[Proxmox REST API]: https://pve.proxmox.com/pve-docs/api-viewer/
[Bolt]: https://puppet.com/docs/bolt/latest/bolt.html
[Proxmox VE]: https://www.proxmox.com/en/proxmox-ve
[patch]: https://github.com/L-Eugene/proxmox-api/pull/1
