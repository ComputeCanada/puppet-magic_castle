function profile::utils::gethostnames_with_class($class_name) >> Array[String] {
  $instances = lookup('terraform.instances')
  $site_all = lookup('magic_castle::site::all')
  $site_tags = lookup('magic_castle::site::tags')

  if $class_name in $site_all {
    return $instances.keys()
  } else {
    $tags = keys($site_tags).filter |$tag| {
      $class_name in $site_tags[$tag]
    }
    return keys($instances).filter |$hostname| {
      !intersection($tags, $instances[$hostname]['tags']).empty
    }
  }
}
