function profile::getreversezone() >> String {
  $interface = profile::getlocalinterface()
  $network = $networking['interfaces'][$interface]['network']
  $network_list = split($network, '[.]')
  $netmask_list = split(profile::getnetmask(), '[.]')

  $filtered_network = $network_list.filter |$i, $v| { $netmask_list[$i] != '0' }

  $zone = join(reverse($filtered_network), '.')
  "${zone}.in-addr.arpa."
}
