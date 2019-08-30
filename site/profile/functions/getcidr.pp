function profile::getcidr() >> String {
  $masklen = netmask_to_masklen(profile::getnetmask())
  "${network_eth0}/${masklen}"
}
