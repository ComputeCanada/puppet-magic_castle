# Shared system wrapper for commands authenticated as the IPA administrator.
class profile::freeipa::kinit_wrapper {
  file { 'kinit_wrapper':
    path   => '/usr/local/bin/kinit_wrapper',
    source => 'puppet:///modules/profile/freeipa/kinit_wrapper',
    mode   => '0755',
  }
}
