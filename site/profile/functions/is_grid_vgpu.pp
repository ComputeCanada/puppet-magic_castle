function profile::is_grid_vgpu() >> Boolean {
  if $facts['nvidia_grid_vgpu'] {
    true
  } elsif $facts['cloud']['provider'] == 'azure' {
    $type = lookup('terraform.self.specs.type')
    (
      $type =~ /^Standard_NV[a-z0-9]*_A10_v5$/ or
      $type =~ /^Standard_NV(12|24|48)s_v3$/ or
      $type =~ /^Standard_NC(4|8|16|64)as_T4_v3$/
    )
  } else {
    false
  }
}
