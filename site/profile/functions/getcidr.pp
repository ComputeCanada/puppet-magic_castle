function profile::getcidr() >> String {
  $interface = split($interfaces, ',')[0]
  $masklen = netmask_to_masklen(profile::getnetmask())
  $network = $networking['interfaces'][$interface]['network']
  "${network}/${masklen}"
}
