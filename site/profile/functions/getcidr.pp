function profile::getcidr() >> String {
  $terraform_cidr = lookup('terraform.network.cidr', String, 'first', '')
  if $terraform_cidr != '' {
    return $terraform_cidr
  }
  $interface = profile::getlocalinterface()
  $masklen = extlib::netmask_to_cidr(profile::getnetmask())
  $ip = $networking['interfaces'][$interface]['ip']
  $network = extlib::cidr_to_network("${ip}/${masklen}")
  "${network}/${masklen}"
}
