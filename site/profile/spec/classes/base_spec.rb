require 'spec_helper'

describe 'profile::base' do
  let(:params) do
    {
      'version' => '1.2.3',
      'packages' => ['htop', 'curl'],
      'admin_email' => admin_email,
    }
  end

  let(:admin_email) { nil }
  let(:os_major) { '8' }
  let(:cloud_provider) { 'aws' }
  let(:virtual) { 'kvm' }

  let(:facts) do
    {
      :os => { 'release' => { 'major' => os_major } },
      :cloud => { 'provider' => cloud_provider },
      :virtual => virtual,
    }
  end

  let(:pre_condition) do
    <<-PUPPET
      class stdlib {}
      class epel {}
      class selinux {}
      class selinux::config {}
      class profile::base::etc_hosts {}
      class profile::base::powertools {}
      class profile::ssh::base {}
      class firewall(String $tag = undef) {}

      define firewall(
        $chain = undef,
        $proto = undef,
        $source = undef,
        $destination = undef,
        $action = undef,
        $uid = undef,
        $tag = undef,
      ) {}

      define selinux::boolean($value = undef) {}
      define sysctl($value = undef, $ensure = undef) {}

      service { 'iptables': }
      service { 'ip6tables': }
      yumrepo { 'epel': }
      class { 'selinux::config': }

      function profile::getcidr() >> String { '10.0.0.0/24' }
    PUPPET
  end

  it { is_expected.to compile.with_all_deps }

  it 'manages base files' do
    is_expected.to contain_file('/etc/magic-castle-release')
      .with_content('Magic Castle release 1.2.3')

    is_expected.to contain_file('/usr/sbin/prepare4image.sh')
      .with_source('puppet:///modules/profile/base/prepare4image.sh')
      .with_mode('0755')

    is_expected.to contain_file('/etc/localtime')
      .with_ensure('link')
      .with_target('/usr/share/zoneinfo/UTC')

    is_expected.to contain_file('/etc/puppetlabs/puppet/csr_attributes.yaml')
      .with_ensure('absent')
  end

  it 'manages base packages' do
    is_expected.to contain_package('selinux-policy')
    is_expected.to contain_package('pciutils').with_ensure('installed')
    is_expected.to contain_package('vim').with_ensure('installed')
    is_expected.to contain_package('unzip').with_ensure('installed')
    is_expected.to contain_package('firewalld').with_ensure('absent')
    is_expected.to contain_package('clustershell')
      .with_ensure('installed')
      .with_require('Yumrepo[epel]')

    is_expected.to contain_package('htop')
      .with_ensure('installed')
      .with_require('Yumrepo[epel]')

    is_expected.to contain_package('curl')
      .with_ensure('installed')
      .with_require('Yumrepo[epel]')
  end

  it 'configures firewall rules' do
    is_expected.to contain_firewall('001 accept all from local network')
      .with_chain('INPUT')
      .with_proto('all')
      .with_source('10.0.0.0/24')
      .with_action('accept')
      .with_tag('mc_bootstrap')

    is_expected.to contain_firewall('001 drop access to metadata server')
      .with_chain('OUTPUT')
      .with_proto('tcp')
      .with_destination('169.254.169.254')
      .with_action('drop')
      .with_uid('! root')
      .with_tag('mc_bootstrap')
  end

  it 'sets up selinux and tmpfiles' do
    is_expected.to contain_selinux__boolean('selinuxuser_tcp_server')

    is_expected.to contain_exec('systemd-tmpfiles --create --prefix=/run/lock/subsys')
      .with_unless('test -d /run/lock/subsys')
      .with_path(['/bin'])
      .with_notify(['Service[iptables]', 'Service[ip6tables]'])
  end

  it 'sets dmesg restriction on non-container systems' do
    is_expected.to contain_sysctl('kernel.dmesg_restrict')
      .with_ensure('present')
      .with_value(1)
  end

  context 'when admin_email is set' do
    let(:admin_email) { 'admin@example.test' }

    it 'creates postrun script' do
      is_expected.to contain_file('/opt/puppetlabs/bin/postrun')
        .with_mode('0700')
        .with_content(/email='admin@example\.test'/)
    end
  end

  context 'when os major is 8' do
    let(:os_major) { '8' }

    it 'installs and enables haveged' do
      is_expected.to contain_package('haveged')
        .with_ensure('installed')
        .with_require('Yumrepo[epel]')

      is_expected.to contain_service('haveged')
        .with_ensure('running')
        .with_enable(true)
        .with_require('Package[haveged]')
    end
  end

  context 'when os major is 9' do
    let(:os_major) { '9' }

    it 'does not manage haveged' do
      is_expected.not_to contain_package('haveged')
      is_expected.not_to contain_service('haveged')
    end
  end

  context 'when running on azure' do
    let(:cloud_provider) { 'azure' }

    it 'includes azure profile' do
      is_expected.to contain_class('profile::base::azure')
      is_expected.to contain_package('WALinuxAgent').with_ensure('purged')
      is_expected.to contain_file('/etc/udev/rules.d/66-azure-storage.rules')
        .with_source('https://raw.githubusercontent.com/Azure/WALinuxAgent/v2.2.48.1/config/66-azure-storage.rules')
        .with_mode('0644')
        .with_checksum('md5')
        .with_checksum_value('51e26bfa04737fc1e1f14cbc8aeebece')
    end
  end

  context 'when running in a container' do
    let(:virtual) { 'container' }

    it 'does not set dmesg restriction' do
      is_expected.not_to contain_sysctl('kernel.dmesg_restrict')
    end
  end
end
