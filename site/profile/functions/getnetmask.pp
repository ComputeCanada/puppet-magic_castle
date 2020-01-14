function profile::getnetmask() >> String {
  if $facts['gce'] {
    # GCP instances netmask is set to /32 but the network netmask is available
    $netmask = $gce['instance']['networkInterfaces'][0]['subnetmask']
  } else {
    $interface = split($interfaces, ',')[0]
    $netmask = $networking['interfaces'][$interface]['netmask']
  }
  $netmask
}
