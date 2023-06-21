function profile::getlocalinterface() >> String {
  $local_ip = lookup("terraform.instances.${facts['networking']['hostname']}.local_ip")
  $interfaces = keys($facts['networking']['interfaces'])
  $search = $interfaces.filter | $interface | {
    $facts['networking']['interfaces'][$interface]['ip'] == $local_ip
  }
  $search[0]
}
