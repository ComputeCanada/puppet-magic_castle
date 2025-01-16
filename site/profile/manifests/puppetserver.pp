class profile::puppetserver {
  tag 'mc_bootstrap'
  include profile::firewall
  include nftables::rules::puppet
}
