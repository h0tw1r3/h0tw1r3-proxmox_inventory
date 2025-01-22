#!/usr/bin/env ruby
# frozen_string_literal: true

require 'rubygems'
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

  def mask(n)
    [ ((1 << 32) - 1) << (32 - n) ].pack('N').bytes.join('.')
  end

  def parse_config_value(value)
    if value.is_a?(String) && value.include?('=')
      value.split(',').map { |pair|
        key, value = pair.split('=', 2)
        unless value
          value = key
          key = 'storage'
        end
        [key, value]
      }.to_h
    else
      value
    end
  end

  def transform_config(config, resource)
    interfaces = nil
    config.each_key do |ck|
      cv = config[ck] = parse_config_value(config[ck])
      if ck =~ %r{(\w+)(\d+)}
        next unless Regexp.last_match(1) == 'net'
        # convert qemu interface=>macaddr to type=>interface and hwaddr=>macaddr
        unless cv.key?('hwaddr')
          device_type = cv.select { |k, v| k if v.match?(%r{^(([A-Za-f\d]{2}):?){6}}) }.keys[0]
          cv['hwaddr'] = cv.delete(device_type).upcase
          cv['type'] = device_type.to_s
        end
        # set qemu net ip from cloudinit
        if config.key?(:"ipconfig#{Regexp.last_match(2)}")
          cv['ip'] = config[:"ipconfig#{Regexp.last_match(2)}"]['ip']
        end
        # convert ip=dhcp
        if cv['ip'] == 'dhcp'
          # convert dhcp to cidr
          if cv['type'] == 'veth'
            # lxc
            begin
              interfaces = @client["nodes/#{resource[:node]}/#{resource[:id]}/interfaces"].get
              interfaces.each do |n|
                cv['ip'] = n[:inet] if n[:hwaddr].casecmp(cv['hwaddr']).zero? && n[:inet]
              end
            rescue ProxmoxAPI::ApiException
              # noop
            end
          else
            # qemu
            begin
              interfaces ||= @client["nodes/#{resource[:node]}/#{resource[:id]}/agent/network-get-interfaces"].get[:result]
              agent_net_intf = interfaces.find do |ani|
                # rjust to work-around osx agent bug when hwaddr starts with zero
                ani.key?(:'hardware-address') && ani[:"hardware-address"].rjust(17, '0').casecmp(cv['hwaddr']).zero?
              end
              if agent_net_intf.class == Hash && agent_net_intf[:'ip-addresses'].empty?
                agent_net_intf[:'ip-addresses'].delete_if { |b| b[:'ip-address-type'] == 'ipv6' }
                unless agent_net_intf[:"ip-addresses"].empty?
                  cv['ip'] = agent_net_intf[:'ip-addresses'][0][:'ip-address']
                end
              end
              cv['name'] = agent_net_intf[:name]
            rescue ProxmoxAPI::ApiException
              # noop
            end
          end
        # convert ip=cidr
        elsif cv['ip']
          begin
            ip, mask = cv['ip'].split('/')
            cv['ip'] = ip
            cv['netmask'] = mask(mask.to_i)
          rescue StandardError => e
            raise e.exception("Message: #{cv}")
          end
        else
          begin
            cv['ip'] = Resolv.getaddress(config[:fqdn])
          rescue Resolv::ResolvError
            # noop
          end
        end
      end
    end
  end

  def build_data(resource)
    config = @client["nodes/#{resource[:node]}/#{resource[:id]}/config?current=1"].get

    # build the fqdn
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

    config = transform_config(config, resource)
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
      !t.key?(:net0) || !t[:net0].key?('ip') || t[:net0]['ip'] == 'dhcp'
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
  Gem::Specification::find_by_name('proxmox-api')
rescue Gem::LoadError
  default_ui = Gem.ui() # lazy loads user_interactions (SilentUI)
  ui = Gem::SilentUI.new
  Gem::DefaultUserInteraction.use_ui ui do
    Gem.configuration.verbose = false
    Gem.install('proxmox-api', '>=1.1.0', 'user_install': true)
  end
end

require 'proxmox_api'

ProxmoxInventory.run if $PROGRAM_NAME == __FILE__
