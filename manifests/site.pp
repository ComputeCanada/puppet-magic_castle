node default {
  $instance_tags = lookup("terraform.instances.${facts['networking']['hostname']}.tags")

  include(lookup('magic_castle::site::all', undef, undef, []))

  $instance_tags.each | $tag | {
    include(lookup("magic_castle::site::tags.${tag}", undef, undef, []))
  }
  $not_tags = lookup('magic_castle::site::not_tags')
  $not_tags.each | $tag, $classes | {
    if ! ($tag in $instance_tags) {
      include($classes)
    }
  }
}
