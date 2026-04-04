function profile::gpu::has_vgpu() >> Boolean {
  if $facts['nvidia_grid_vgpu'] {
    true
  } else {
    $grid_vgpu_types = lookup('profile::gpu::install::vgpu::grid_vgpu_types', undef, undef, [])
    $type = lookup('terraform.self.specs.type')
    $grid_vgpu_types.any|$regex| { $type =~ Regexp($regex) }
  }
}
