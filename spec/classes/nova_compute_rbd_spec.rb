#
# Copyright (C) 2014 eNovance SAS <licensing@enovance.com>
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
#
# Unit tests for nova::compute::rbd class
#

require 'spec_helper'

describe 'nova::compute::rbd' do

  let :params do
    { :libvirt_rbd_user             => 'nova',
      :libvirt_rbd_secret_uuid      => false,
      :libvirt_images_rbd_pool      => 'rbd',
      :libvirt_images_rbd_ceph_conf => '/etc/ceph/ceph.conf',
      :ephemeral_storage            => true }
  end

  shared_examples_for 'nova compute rbd' do

    it { is_expected.to contain_class('nova::params') }

    it 'configure nova.conf with default parameters' do
        is_expected.to contain_nova_config('libvirt/images_type').with_value('rbd')
        is_expected.to contain_nova_config('libvirt/images_rbd_pool').with_value('rbd')
        is_expected.to contain_nova_config('libvirt/images_rbd_ceph_conf').with_value('/etc/ceph/ceph.conf')
        is_expected.to contain_nova_config('libvirt/rbd_user').with_value('nova')
    end

    it 'installs client package' do
      is_expected.to contain_package('ceph-client-package').with(
        'name'   => platform_params[:ceph_client_package],
        'ensure' => 'present'
      )
    end

    context 'when overriding default parameters' do
      before :each do
        params.merge!(
          :libvirt_rbd_user             => 'joe',
          :libvirt_rbd_secret_uuid      => false,
          :libvirt_images_rbd_pool      => 'AnotherPool',
          :libvirt_images_rbd_ceph_conf => '/tmp/ceph.conf'
        )
      end

      it 'configure nova.conf with overridden parameters' do
          is_expected.to contain_nova_config('libvirt/images_type').with_value('rbd')
          is_expected.to contain_nova_config('libvirt/images_rbd_pool').with_value('AnotherPool')
          is_expected.to contain_nova_config('libvirt/images_rbd_ceph_conf').with_value('/tmp/ceph.conf')
          is_expected.to contain_nova_config('libvirt/rbd_user').with_value('joe')
      end
    end

    context 'when using cephx' do
      before :each do
        params.merge!(
          :libvirt_rbd_secret_uuid => 'UUID',
          :rbd_keyring             => 'client.rbd_test'
        )
      end

      it 'configure nova.conf with RBD secret UUID' do
          is_expected.to contain_nova_config('libvirt/rbd_secret_uuid').with_value('UUID')
      end

      it 'configure ceph on compute nodes' do
        verify_contents(catalogue, '/etc/nova/secret.xml', [
          "<secret ephemeral=\'no\' private=\'no\'>",
          "  <usage type=\'ceph\'>",
          "    <name>client.rbd_test secret</name>",
          "  </usage>",
          "  <uuid>UUID</uuid>",
          "</secret>"
        ])
        is_expected.to contain_exec('get-or-set virsh secret').with(
          :command =>  '/usr/bin/virsh secret-define --file /etc/nova/secret.xml | /usr/bin/awk \'{print $2}\' | sed \'/^$/d\' > /etc/nova/virsh.secret',
          :unless  => '/usr/bin/virsh secret-list | grep -i UUID',
          :require => ['File[/etc/nova/secret.xml]', 'Service[libvirt]'],
        )
        is_expected.to contain_exec('set-secret-value virsh').with(
          :command => "/usr/bin/virsh secret-set-value --secret UUID --base64 $(ceph auth get-key client.rbd_test)"
        )
      end
    end

    context 'when using cephx and passing libvirt_rbd_secret_key' do
      before :each do
        params.merge!(
          :libvirt_rbd_secret_uuid => 'UUID',
          :libvirt_rbd_secret_key  => 'LIBVIRT/SECRET/KEY',
        )
      end

      it 'set libvirt secret key from passed key' do
        is_expected.to contain_exec('set-secret-value virsh').with(
          :command => "/usr/bin/virsh secret-set-value --secret #{params[:libvirt_rbd_secret_uuid]} --base64 #{params[:libvirt_rbd_secret_key]}"
        )
      end
    end

    context 'when using cephx but disabling ephemeral storage' do
      before :each do
        params.merge!(
          :libvirt_rbd_secret_uuid      => 'UUID',
          :rbd_keyring                  => 'client.rbd_test',
          :ephemeral_storage            => false
        )
      end

      it 'should only set user and secret_uuid in nova.conf ' do
          is_expected.to_not contain_nova_config('libvirt/images_rbd_pool').with_value('rbd')
          is_expected.to_not contain_nova_config('libvirt/images_rbd_ceph_conf').with_value('/etc/ceph/ceph.conf')
          is_expected.to contain_nova_config('libvirt/rbd_user').with_value('nova')
          is_expected.to contain_nova_config('libvirt/rbd_secret_uuid').with_value('UUID')
      end

      it 'configure ceph on compute nodes' do
        verify_contents(catalogue, '/etc/nova/secret.xml', [
          "<secret ephemeral=\'no\' private=\'no\'>",
          "  <usage type=\'ceph\'>",
          "    <name>client.rbd_test secret</name>",
          "  </usage>",
          "  <uuid>UUID</uuid>",
          "</secret>"
        ])
        is_expected.to contain_exec('get-or-set virsh secret').with(
          :command =>  '/usr/bin/virsh secret-define --file /etc/nova/secret.xml | /usr/bin/awk \'{print $2}\' | sed \'/^$/d\' > /etc/nova/virsh.secret',
          :unless  => '/usr/bin/virsh secret-list | grep -i UUID',
          :require => ['File[/etc/nova/secret.xml]', 'Service[libvirt]'],
        )
        is_expected.to contain_exec('set-secret-value virsh').with(
          :command => "/usr/bin/virsh secret-set-value --secret UUID --base64 $(ceph auth get-key client.rbd_test)"
        )
      end
    end

    context 'when not managing ceph client' do
      before :each do
        params.merge!(
          :manage_ceph_client => false
        )
      end

      it { is_expected.to_not contain_package('ceph-client-package') }
    end
  end

  context 'on Debian platforms' do
    let :facts do
      @default_facts.merge({ :osfamily => 'Debian' })
    end

    let :platform_params do
      { :ceph_client_package => 'ceph'}
    end

    it_configures 'nova compute rbd'
  end

  context 'on RedHat platforms' do
    let :facts do
      @default_facts.merge({ :osfamily => 'RedHat' })
    end

    let :platform_params do
      { :ceph_client_package => 'ceph-common' }
    end

    it_configures 'nova compute rbd'
  end

end
