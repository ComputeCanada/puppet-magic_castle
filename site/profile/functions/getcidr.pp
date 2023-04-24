function profile::getcidr() >> String {
  $interface = $networking['primary']
  $masklen = netmask_to_masklen(profile::getnetmask())
  $network = $networking['interfaces'][$interface]['network']
  "${network}/${masklen}"
}
