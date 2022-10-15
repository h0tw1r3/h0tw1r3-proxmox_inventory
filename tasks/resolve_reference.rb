#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../ruby_task_helper/files/task_helper.rb'
require_relative '../../ruby_plugin_helper/lib/plugin_helper.rb'
require 'proxmox_api'

# bolt resolver plugin
class ProxmoxInventory < TaskHelper
  include RubyPluginHelper

  attr_accessor :client

  def convert_key_value_string(value)
    value.split(',').map { |pair|
      key, value = pair.split('=')
      if key == 'ip'
        value.gsub!(%r{/\d+$}, '')
      end
      [key, value]
    }.to_h
  end

  def build_data(resource, config)
    config.keys.grep(%r{^(net|mp|unused)\d+}).map { |v| v.to_s.gsub!(%r{\d+}, '').to_sym }.each do |k|
      config[k] = []
    end
    config.each { |k, v|
      if %r{^(?<index>net|mp|unused)(?<count>\d+)} =~ k.to_s
        config[index.to_sym][count.to_i] = convert_key_value_string(v)
      end
    }.merge(resource)
  end

  def client_config(opts)
    config = {}

    if [:username, :password, :realm].all? { |s| opts.key?(s) }
      config[:username] = opts[:username]
      config[:password] = opts[:password]
      config[:realm] = opts[:realm]
      if opts.key?(:otp)
        config[:otp] = opts[:otp]
      end
    elsif [:token, :secret].all? { |s| opts.key?(s) }
      config[:token] = opts[:token]
      config[:secret] = opts[:secret]
    else
      msg = "You must provide either 'username', 'password' and 'realm' or 'token' and 'secret' for the Proxmox plugin"
      raise TaskHelper::Error.new(msg, 'bolt-plugin/validation-error')
    end

    if opts.key?(:port)
      config[:port] = opts[:port].to_i
    end
    if opts.key?(:verify_ssl)
      config[:verify_ssl] = opts[:verify_ssl]
    end

    [ opts[:host], config ]
  end

  def build_client(opts)
    return client if client

    config = client_config(opts)

    ProxmoxAPI.new(*config)
  end

  def resolve_reference(opts)
    template = opts.delete(:target_mapping) || {}
    unless template.key?(:uri) || template.key?(:name)
      msg = "You must provide a 'name' or 'uri' in 'target_mapping' for the Proxmox plugin"
      raise TaskHelper::Error.new(msg, 'bolt-plugin/validation-error')
    end

    client = build_client(opts)

    # Retrieve a list resources from the cluster
    resources = client.cluster.resources.get.select do |res|
      res[:node] if ['lxc', 'qemu'].include?(res[:type]) && ['running'].include?(res[:status])
    end

    # Retrieve node configuration
    targets = resources.map do |res|
      build_data(res, client["nodes/#{res[:node]}/#{res[:id]}/config?current=1"].get)
    end

    attributes = required_data(template)
    target_data = targets.map do |target|
      attributes.each_with_object({}) do |attr, acc|
        attr = attr.first
        acc[attr] = target.key?(attr.to_sym) ? target[attr.to_sym] : nil
      end
    end

    target_data.map { |data| apply_mapping(template, data) }
  end

  def task(opts = {})
    targets = resolve_reference(opts)
    { value: targets }
  end
end

# This bolt project requires the proxmox-api gem
# TODO find the apropriate place to put this, if at all?
begin
  require 'proxmox_api'
rescue LoadError
  require 'rubygems'
  Gem.install('proxmox_api', '>0', 'user_install': true)
end

ProxmoxInventory.run if $PROGRAM_NAME == __FILE__
