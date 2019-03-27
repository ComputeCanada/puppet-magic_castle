function profile::getcidr() >> String {
  if $facts['gce'] {
    # GCP instances netmask is set to /32 but the network netmask is available
    $netmask = $gce['instance']['networkInterfaces'][0]['subnetmask']
  }
  $masklen = netmask_to_masklen("$netmask")
  "$network/$masklen"
}
