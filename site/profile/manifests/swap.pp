class profile::swap (
  String $size = '1 GB',
  Integer $swappiness = 10,
) {
  if $facts['virtual'] !~ /^(container|lxc).*$/ {
    if '/mnt/ephemeral0' in $facts['mountpoints'] {
      $swapfile = '/mnt/ephemeral0/swap'
    } else {
      $swapfile = '/mnt/swap'
    }
    $swapfilesize = $size
    swap_file::files { 'default':
      ensure       => present,
      swapfile     => $swapfile,
      swapfilesize => $swapfilesize,
    }
    sysctl { 'vm.swappiness':
      ensure => 'present',
      value  => $swappiness,
    }
  }
}
