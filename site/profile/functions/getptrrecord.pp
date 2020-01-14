function profile::getptrrecord() >> String {
  $interface = split($interfaces, ',')[0]
  $ip = $networking['interfaces'][$interface]['ip']
  $ip_list = split($ip, '[.]')
  $netmask_list = split(profile::getnetmask(), '[.]')

  $filtered_ip = $ip_list.filter |$i, $v| { $netmask_list[$i] == '0' }

  join(reverse($filtered_ip), '.')
}
