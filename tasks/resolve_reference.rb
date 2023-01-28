#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../ruby_task_helper/files/task_helper.rb'
require_relative '../../ruby_plugin_helper/lib/plugin_helper.rb'

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

  def build_agent(resource, client)
    net_conf = (client["nodes/#{resource[:node]}/#{resource[:id]}/agent/network-get-interfaces"].get)[:result]
    net_conf.delete_if { |x| x[:name] =~ %r{^lo} }.map do |x|
      x.delete(:statistics)
      x['hwaddr'] = x.delete(:"hardware-address")
      x[:"ip-addresses"].delete_if { |b| b[:"ip-address-type"] == 'ipv6' }
      x['ip'] = x.delete(:"ip-addresses")[0][:"ip-address"]
      x['name'] = x.delete(:name)
    end
    { 'net' => net_conf }
  end

  def build_data(resource, client)
    config = client["nodes/#{resource[:node]}/#{resource[:id]}/config?current=1"].get

    if config.key?(:agent) && config[:agent].start_with?('1')
      begin
        config[:agent] = build_agent(resource, client)
      rescue
        config[:agent] = nil
      end
    end

    config.keys.grep(%r{^(ipconfig|net|mp|unused)\d+}).each do |v|
      config[v.to_s.gsub!(%r{\d+}, '').to_sym] = []
    end
    config.each { |k, v|
      if %r{^(?<index>ipconfig|net|mp|unused)(?<count>\d+)} =~ k.to_s
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

  def filter_targets(targets)
    targets.delete_if do |t|
      t[:type] == 'qemu' && t[:agent].class != Hash
    end
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
      res[:node] if res[:type] == opts[:type] && ['running'].include?(res[:status])
    end

    # Retrieve node configuration
    targets = resources.map do |res|
      build_data(res, client)
    end

    filter_targets(targets)

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
# TODO find the appropriate place to put this, if at all?
begin
  require 'proxmox_api'
rescue LoadError
  require 'rubygems'
  ui = Gem::SilentUI.new
  Gem::DefaultUserInteraction.use_ui ui do
    Gem.configuration.verbose = false
    Gem.install('proxmox-api', '>=1.1.0', 'user_install': true)
  end
  require 'proxmox_api'
end

ProxmoxInventory.run if $PROGRAM_NAME == __FILE__
