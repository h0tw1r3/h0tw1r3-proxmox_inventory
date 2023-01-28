# Changelog

All notable changes to this project will be documented in this file.

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
