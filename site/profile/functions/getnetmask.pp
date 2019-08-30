function profile::getnetmask() >> String {
  if $facts['gce'] {
    # GCP instances netmask is set to /32 but the network netmask is available
    $netmask_eth0 = $gce['instance']['networkInterfaces'][0]['subnetmask']
  }
  $netmask_eth0
}
