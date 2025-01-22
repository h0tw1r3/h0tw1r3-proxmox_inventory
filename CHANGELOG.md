# Changelog

All notable changes to this project will be documented in this file.

## Release 0.8.0

* Bolt 4 support

## Release 0.7.1

* Fix error when IP is not set

## Release 0.7.0

* BREAKING: `net` is no longer an array, use `net0` instead.
* Default uri is now `net0.ip`

## Release 0.6.2

* Fix resolving container DHCP ip address

## Release 0.6.0

* Support resolving container DHCP ip address

## Release 0.5.0

* Fix missing qemu targets with Proxmox 8
* Add Puppet 8, drop Puppet 6 support

## Release 0.4.0

* Provide a default target mapping
* Add fqdn attribute and map to node name by default
* Remove qemu specific agent attribute, normalize net attribute between lxc
  and qemu.  `agent.net.0.ip` is now `net.0.ip` (same as lxc)
* Fix inventory error when nodes have interfaces without ip addresses
* Work-around OSX qemu agent hwaddr reporting bug

## Release 0.3.0

* Fix inventory error when QEMU VM's have the agent feature enabled but
  said agent is not running or reporting an IP address.

## Release 0.2.3

* Fix automatic install of the proxmox-api gem

## Release 0.2.1

* Token support now working with update to proxmox-api gem

## Release 0.2.0

* New required `type` parameter accepts two possible values; _lxc_, _qemu_
* Filter qemu VMs without agent running

## Release 0.1.0

Initial public release
