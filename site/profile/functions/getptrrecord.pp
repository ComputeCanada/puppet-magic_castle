function profile::getptrrecord() >> String {
  $ip_list = split($ipaddress_eth0, '[.]')
  $netmask_list = split(profile::getnetmask(), '[.]')

  $filtered_ip = $ip_list.filter |$i, $v| { $netmask_list[$i] == '0' }

  join(reverse($filtered_ip), '.')
}
