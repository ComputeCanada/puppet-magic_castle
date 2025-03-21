function profile::utils::getcidr() >> String {
  $interface = profile::utils::getlocalinterface()
  $masklen = extlib::netmask_to_cidr(profile::utils::getnetmask())
  $ip = $networking['interfaces'][$interface]['ip']
  $network = extlib::cidr_to_network("${ip}/${masklen}")
  "${network}/${masklen}"
}
