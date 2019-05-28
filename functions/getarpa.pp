function profile::getarpa() >> String {
  $network_list = $network.split(".")
  $network_list.reverse!
  $network_list.delete('0')
  $network_list.join('.')+'.in-addr.arpa.'
}
