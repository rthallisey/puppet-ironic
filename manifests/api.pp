#
# Copyright (C) 2013 eNovance SAS <licensing@enovance.com>
#
# Author: Emilien Macchi <emilien.macchi@enovance.com>
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# Configure the API service in Ironic
#
# === Parameters
#
# [*host_ip*]
#   (optional) The listen IP for the Ironic API server.
#   Should be an valid IP address
#   Defaults to '0.0.0.0'.
#
# [*port*]
#   (optional) The port for the Ironic API server.
#   Should be an valid port
#   Defaults to '0.0.0.0'.
#
# [*max_limit*]
#   (optional) The maximum number of items returned in a single response
#   from a collection resource.
#   Should be an valid interger
#   Defaults to '1000'.
#
# [*auth_host*]
#   (optional) The IP of the server running keystone
#   Defaults to '127.0.0.1'
#
# [*auth_port*]
#   (optional) The port to use when authenticating against Keystone
#   Defaults to 35357
#
# [*auth_protocol*]
#   (optional) The protocol to use when authenticating against Keystone
#   Defaults to 'http'
#
# [*auth_uri*]
#   (optional) The uri of a Keystone service to authenticate against
#   Defaults to false
#
# [*auth_admin_prefix*]
#   (optional) Prefix to prepend at the beginning of the keystone path
#   Defaults to false
#
# [*auth_version*]
#   (optional) API version of the admin Identity API endpoint
#   for example, use 'v3.0' for the keystone version 3.0 api
#   Defaults to false
#
# [*admin_tenant_name*]
#   (optional) The name of the tenant to create in keystone for use by the ironic services
#   Defaults to 'services'
#
# [*admin_user*]
#   (optional) The name of the user to create in keystone for use by the ironic services
#   Defaults to 'ironic'
#
# [*neutron_url*]
#   (optional) The Neutron URL to be used for requests from ironic
#   Defaults to false
#
# [*admin_password*]
#   (required) The password to set for the ironic admin user in keystone
#
# [*enabled_drivers*]
#   The back-end drivers for Ironic
#   Defaults to agent_ssh
#
# [*swift_temp_url_key*]
#  (required) The temporaty url key for Ironic to access Swift
#

class ironic::api (
  $package_ensure    = 'present',
  $enabled           = true,
  $host_ip           = '0.0.0.0',
  $port              = '6385',
  $max_limit         = '1000',
  $auth_host         = '127.0.0.1',
  $auth_port         = '35357',
  $auth_protocol     = 'http',
  $auth_uri          = false,
  $auth_admin_prefix = false,
  $auth_version      = false,
  $admin_tenant_name = 'services',
  $admin_user        = 'ironic',
  $neutron_url       = false,
  $enabled_drivers   = 'agent_ssh',
  $admin_password,
  $swift_temp_url_key,
) {

  include ironic::params
  include ironic::policy

  Ironic_config<||> ~> Service['ironic-api']
  Class['ironic::policy'] ~> Service['ironic-api']

  # Install package
  if $::ironic::params::api_package {
    Package['ironic-api'] -> Class['ironic::policy']
    Package['ironic-api'] -> Service['ironic-api']
    Package['ironic-api'] -> Ironic_config<||>
    package { 'ironic-api':
      ensure => $package_ensure,
      name   => $::ironic::params::api_package,
    }
  }

  if $enabled {
    $ensure = 'running'
  } else {
    $ensure = 'stopped'
  }

  # Manage service
  service { 'ironic-api':
    ensure    => $ensure,
    name      => $::ironic::params::api_service,
    enable    => $enabled,
    hasstatus => true,
  }

  # Configures 'glance/swift_account'
  ironic_admin_tenant_id_setter {'swift_account':
    ensure           => present,
    tenant_name      => $admin_tenant_name,
    auth_url         => "${auth_protocol}://${auth_host}:35357/v2.0",
    auth_username    => $admin_user,
    auth_password    => $admin_password,
    auth_tenant_name => $admin_tenant_name,
  }

  # Configure ironic.conf
  ironic_config {
    'api/host_ip':                 value => $host_ip;
    'api/port':                    value => $port;
    'api/max_limit':               value => $max_limit;
    'DEFAULT/enabled_drivers':     value => $enabled_drivers;
    'glance/swift_temp_url_key':   value => $swift_temp_url_key, secret => true;
    'glance/swift_account':        value => $swift_account;
  }

  # Post temp_url_key to swift
  exec { 'swift-temp-url-key-post':
    command     => "swift post -m temp-url-key:${swift_temp_url_key}",
    path        => ['/bin', '/usr/bin'],
    subscribe   => File['/etc/ironic/ironic.conf'],
    refreshonly => true,
  }

  if $neutron_url {
    ironic_config { 'neutron/url': value => $neutron_url; }
  } else {
    ironic_config { 'neutron/url': value => "${auth_protocol}://${auth_host}:9696/"; }
  }

  if $auth_uri {
    ironic_config { 'keystone_authtoken/auth_uri': value => $auth_uri; }
  } else {
    ironic_config { 'keystone_authtoken/auth_uri': value => "${auth_protocol}://${auth_host}:5000/"; }
  }

  if $auth_version {
    ironic_config { 'keystone_authtoken/auth_version': value => $auth_version; }
  } else {
    ironic_config { 'keystone_authtoken/auth_version': ensure => absent; }
  }

  ironic_config {
    'keystone_authtoken/auth_host':         value => $auth_host;
    'keystone_authtoken/auth_port':         value => $auth_port;
    'keystone_authtoken/auth_protocol':     value => $auth_protocol;
    'keystone_authtoken/admin_tenant_name': value => $admin_tenant_name;
    'keystone_authtoken/admin_user':        value => $admin_user;
    'keystone_authtoken/admin_password':    value => $admin_password, secret => true;
  }

  if $auth_admin_prefix {
    validate_re($auth_admin_prefix, '^(/.+[^/])?$')
    ironic_config {
      'keystone_authtoken/auth_admin_prefix': value => $auth_admin_prefix;
    }
  } else {
    ironic_config {
      'keystone_authtoken/auth_admin_prefix': ensure => absent;
    }
  }

}
