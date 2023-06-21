function profile::getcidr() >> String {
  $interface = profile::getlocalinterface()
  $masklen = netmask_to_masklen(profile::getnetmask())
  $network = $networking['interfaces'][$interface]['network']
  "${network}/${masklen}"
}
