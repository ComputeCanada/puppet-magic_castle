node default {
  $instance_tags = lookup("terraform.instances.${facts['networking']['hostname']}.tags")

  $include_all = lookup('magic_castle::site::all', undef, undef, [])

  $include_tags = flatten(
    $instance_tags.map | $tag | {
      lookup("magic_castle::site::tags.${tag}", undef, undef, [])
    }
  )

  $include_not_tags = flatten(
    lookup('magic_castle::site::not_tags', undef, undef, {}).map | $tag, $classes | {
      if ! ($tag in $instance_tags) {
        $classes
      } else {
        []
      }
    }
  )

  if lookup('magic_castle::site::enable_chaos', undef, undef, false) {
    $classes = shuffle($include_all + $include_tags + $include_not_tags)
    notify { 'Chaos order':
      message => String($classes),
    }
  } else {
    $classes = $include_all + $include_tags + $include_not_tags
  }
  include($classes)
}
