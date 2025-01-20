function profile::generate_slurm_node_line($name, $attr, $comp_weight) >> String {
  if $attr['specs']['gpus'] > 0 {
    if $attr['specs']['mig'] and ! $attr['specs']['mig'].empty {
      $gpu = $attr['specs']['mig'].map|$key,$value| {
        ['gpu', $key, $value * $attr['specs']['gpus']].join(':')
      }.join(',')
    } else {
      $gpu = "gpu:${attr['specs']['gpus']}"
    }
    if $attr['specs']['shard'] and ! $attr['specs']['shard'].empty {
      $shard = ",shard:${attr['specs']['shard']}"
    } else {
      $shard = ''
    }
    $gres = "${gpu}${shard}"
  } else {
    $gres = 'gpu:0'
  }
  $weight = pick($attr['specs']['weight'], $comp_weight)
  "NodeName=${name} CPUs=${attr['specs']['cpus']} RealMemory=${attr['specs']['ram']} Gres=${gres} Weight=${weight}"
}
