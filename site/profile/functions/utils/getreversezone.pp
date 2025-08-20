function profile::utils::getreversezone() >> String {
  $interface = profile::utils::getlocalinterface()
  $network = $networking['interfaces'][$interface]['network']
  $network_list = split($network, '[.]')
  $netmask_list = split(profile::utils::getnetmask(), '[.]')

  $filtered_network = $network_list.filter |$i, $v| { $netmask_list[$i] != '0' }

  $zone = join(reverse($filtered_network), '.')
  "${zone}.in-addr.arpa."
}
