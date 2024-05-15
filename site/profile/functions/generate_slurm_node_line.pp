function profile::generate_slurm_node_line($name, $attr, $weight) >> String {
  if $attr['specs']['gpus'] > 0 {
    if $attr['specs']['mig'] and ! $attr['specs']['mig'].empty {
      $gres = $attr['specs']['mig'].map|$key,$value| {
        ['gpu', $key, $value * $attr['specs']['gpus']].join(':')
      }.join(',')
    } else {
      $gres = "gpu:${attr['specs']['gpus']}"
    }
  } else {
    $gres = 'gpu:0'
  }
  "NodeName=${name} CPUs=${attr['specs']['cpus']} RealMemory=${attr['specs']['ram']} Gres=${gres} Weight=${weight}"
}
