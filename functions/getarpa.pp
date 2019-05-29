function profile::getarpa() >> String {
  $network_list = split($network, '[.]')
  $inv_network_list = reverse($network_list)
  $prefix = join($inv_network_list - ['0'], '.')
  "${prefix}.in-addr.arpa."
}
