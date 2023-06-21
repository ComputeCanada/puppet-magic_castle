function profile::getnetmask() >> String {
  if $facts['gce'] {
    # GCP instances netmask is set to /32 but the network netmask is available
    $netmask = $gce['instance']['networkInterfaces'][0]['subnetmask']
  } else {
    $interface = profile::getlocalinterface()
    $netmask = $networking['interfaces'][$interface]['netmask']
  }
  $netmask
}
