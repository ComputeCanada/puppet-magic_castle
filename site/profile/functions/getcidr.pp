function profile::getcidr() >> String {
  $interface = profile::getlocalinterface()
  $masklen = extlib::netmask_to_cidr(profile::getnetmask())
  $ip = $networking['interfaces'][$interface]['ip']
  $network = extlib::cidr_to_network("${ip}/${masklen}")
  "${network}/${masklen}"
}
