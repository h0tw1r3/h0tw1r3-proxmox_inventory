#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../ruby_task_helper/files/task_helper.rb'
require_relative '../../ruby_plugin_helper/lib/plugin_helper.rb'
require 'resolv'

# bolt resolver plugin
class ProxmoxInventory < TaskHelper
  include RubyPluginHelper

  attr_accessor :client
  attr_accessor :template
  attr_accessor :node_dns

  def initialize
    super()
    @node_dns = {}
  end

  def convert_key_value_string(value)
    value.split(',').map { |pair|
      key, value = pair.split('=')
      if key == 'ip'
        value.gsub!(%r{/\d+$}, '')
      end
      [key, value]
    }.to_h
  end

  # Resolve and format qemu netX interfaces to look similar to lxc
  # QEMU
  # :net=>[{"virtio"=>"9E:5C:5F:5F:D0:1B", "bridge"=>"vmbr1"}]
  # LXC
  # :net=>[{"name"=>"eth0", "bridge"=>"vmbr1", "gw"=>"192.168.47.254", "hwaddr"=>"FA:77:1B:D7:3C:E2", "ip"=>"192.168.47.23", "type"=>"veth"}]
  def resolve_qemu_network(resource, config)
    unless config.key?(:net)
      return
    end

    config[:net].each.map do |value|
      device_type = value.select { |k, v| k if v.match?(%r{^(([A-Za-f\d]{2}):?){6}}) }.keys[0]
      value['hwaddr'] = value.delete(device_type).upcase
      value.merge!({ 'type' => device_type.to_s })
    end

    begin
      agent_network = @client["nodes/#{resource[:node]}/#{resource[:id]}/agent/network-get-interfaces"].get[:result]
    rescue ProxmoxAPI::ApiException
      # no agent running?
      return
    end

    begin
      config[:net].each.map do |value|
        agent_net_intf = agent_network.find do |ani|
          # rjust to work-around osx agent bug when hwaddr starts with zero
          ani.key?(:'hardware-address') && ani[:"hardware-address"].rjust(17, '0').casecmp(value['hwaddr']).zero?
        end
        next unless agent_net_intf.class == Hash
        unless agent_net_intf[:'ip-addresses'].empty?
          agent_net_intf[:'ip-addresses'].delete_if { |b| b[:'ip-address-type'] == 'ipv6' }
          unless agent_net_intf[:"ip-addresses"].empty?
            value['ip'] = agent_net_intf[:'ip-addresses'][0][:'ip-address']
          end
        end
        value['name'] = agent_net_intf[:name]
      end
    rescue StandardError => e
      raise TaskHelper::Error.new("#{e.backtrace[0]} #{e.message} #{agent_network}", 'bolt-plugin/validation-error')
    end
  end

  def resolve_lxc_network(resource, config)
    unless config.key?(:net)
      return
    end

    config[:net].each.map do |value|
      next unless value['ip'] == 'dhcp'
      begin
        @interfaces ||= @client["nodes/#{resource[:node]}/#{resource[:id]}/interfaces"].get
      rescue ProxmoxAPI::ApiException
        @interfaces ||= []
      end
      @interfaces.each { |n| value['ip'] = n[:inet].split('/')[0] if n[:hwaddr].casecmp(value['hwaddr']) }
      next unless value['ip'] == 'dhcp'
      begin
        value['ip'] = Resolv::DNS.open { |x| x.getaddress(value['ip']) }
      rescue Resolv::ResolvError
        # noop
      end
    end
  end

  def build_data(resource)
    config = @client["nodes/#{resource[:node]}/#{resource[:id]}/config?current=1"].get

    config.keys.grep(%r{^(ipconfig|net|mp|unused)\d+}).each do |v|
      config[v.to_s.gsub!(%r{\d+}, '').to_sym] = []
    end
    config.each do |k, v|
      if %r{^(?<index>ipconfig|net|mp|unused)(?<count>\d+)} =~ k.to_s
        config[index.to_sym][count.to_i] = convert_key_value_string(v)
      end
    end

    if config.key?(:agent) && config[:agent] =~ %r{(^1|enabled=1)}
      resolve_qemu_network(resource, config)
    elsif resource[:id].match?(%r{^lxc})
      resolve_lxc_network(resource, config)
    end

    config[:fqdn] = if config.key?(:hostname)
                      config[:hostname].to_s
                    else
                      config[:name].to_s
                    end

    config[:fqdn] += if config.key?(:searchdomain)
                       ".#{config[:searchdomain]}"
                     else
                       ".#{get_node_dns(resource[:node])[:search]}"
                     end

    config.merge(resource)
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
    config = client_config(opts)
    @client = ProxmoxAPI.new(*config)
  end

  def get_node_dns(node)
    unless @node_dns.key?('search')
      @node_dns = @client["nodes/#{node}/dns"].get
    end
    @node_dns
  end

  def filter_targets(targets)
    targets.delete_if do |t|
      !t.key?(:net) || t[:net].class != Array || !t[:net][0].key?('ip') || t[:net][0]['ip'] == 'dhcp'
    end
  end

  def resolve_reference(opts)
    @template = opts.delete(:target_mapping) || {}
    unless @template.key?(:uri) || @template.key?(:name)
      msg = "You must provide a 'name' or 'uri' in 'target_mapping' for the Proxmox plugin"
      raise TaskHelper::Error.new(msg, 'bolt-plugin/validation-error')
    end

    build_client(opts)

    # Retrieve a list resources from the cluster
    resources = @client['cluster/resources?type=vm'].get.select do |res|
      res[:node] if (res[:type] == opts[:type] || opts[:type] == 'all') && ['running'].include?(res[:status])
    end

    # Retrieve node configuration
    targets = resources.map do |res|
      build_data(res)
    end

    filter_targets(targets)

    attributes = required_data(@template)
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
