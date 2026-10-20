# Validate an explicitly assigned LDAP ID or contiguous range of IDs.
function profile::validate_ldap_id (
  Integer[1] $id,
  String $label,
  Integer[1] $count = 1,
) >> Undef {
  $id_start = lookup('profile::freeipa::server::id_start', Integer[1])
  $id_max = lookup('profile::freeipa::server::id_max', Integer[1])
  $last_id = $id + $count - 1

  if $id_max < $id_start {
    fail('profile::freeipa::server::id_max must be greater than or equal to id_start')
  }
  if $id < $id_start or $last_id > $id_max {
    fail("${label}: requested IDs ${id}-${last_id} must be within the FreeIPA range ${id_start}-${id_max}")
  }
  undef
}
