function profile::utils::getptrrecord() >> String {
  $interface = profile::utils::getlocalinterface()
  $ip = $networking['interfaces'][$interface]['ip']
  $ip_list = split($ip, '[.]')
  $netmask_list = split(profile::utils::getnetmask(), '[.]')

  $filtered_ip = $ip_list.filter |$i, $v| { $netmask_list[$i] == '0' }

  join(reverse($filtered_ip), '.')
}
