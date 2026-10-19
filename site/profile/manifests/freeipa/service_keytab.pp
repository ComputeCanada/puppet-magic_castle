# Register an IPA service on script/config changes and retrieve its keytab when missing.
# @param service_name Host-qualified service principal, without the realm.
# @param config_path Absolute path to the service JSON configuration file.
# @param keytab_path Absolute path to the service keytab.
# @param group Group allowed to read the keytab.
# @param role_name Role assigned to the service.
# @param role_description Description used when creating the role.
# @param privileges Existing or custom privileges assigned to the role.
# @param aliases Additional service principals, without the realm.
# @param keytab_principal Principal to retrieve; defaults to service_name.
# @param permissions Permission names mapped to permission_add options.
# @param custom_privileges Privilege names mapped to their permission names.
# @param owner Keytab owner.
# @param mode Keytab permissions.
define profile::freeipa::service_keytab (
  String[1] $service_name,
  Stdlib::Absolutepath $config_path,
  Stdlib::Absolutepath $keytab_path,
  String[1] $group,
  String[1] $role_name,
  String[1] $role_description,
  Array[String[1]] $privileges,
  Array[String[1]] $aliases = [],
  String[1] $keytab_principal = $service_name,
  Hash[String[1], Hash] $permissions = {},
  Hash[String[1], Array[String[1]]] $custom_privileges = {},
  String[1] $owner = 'root',
  String[1] $mode = '0640',
) {
  include profile::freeipa::kinit_wrapper

  $wrapper_path = '/usr/local/bin/kinit_wrapper'
  $service_registration = '/usr/local/sbin/register_service.py'
  ensure_resource(
    'file',
    $service_registration,
    {
      'ensure' => file,
      'owner'  => 'root',
      'group'  => 'root',
      'mode'   => '0600',
      'source' => 'puppet:///modules/profile/freeipa/register_service.py',
    }
  )

  $ipa_domain = lookup('profile::freeipa::base::ipa_domain')
  $ipa_passwd = lookup('profile::freeipa::server::admin_password')
  $config = {
    'service'           => $service_name,
    'realm'             => upcase($ipa_domain),
    'aliases'           => $aliases,
    'role'              => $role_name,
    'description'       => $role_description,
    'privileges'        => $privileges,
    'permissions'       => $permissions,
    'custom_privileges' => $custom_privileges,
  }

  file { $config_path:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => stdlib::to_json_pretty($config),
  }

  exec { "ipa_register_service_${title}":
    command     => shellquote($wrapper_path, 'ipa', 'console', $service_registration),
    refreshonly => true,
    subscribe   => [File[$service_registration], File[$config_path]],
    require     => [File[$wrapper_path], Exec['ipa-install']],
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}", "IPA_SERVICE_CONFIG=${config_path}"],
    path        => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
  }

  $getkeytab_command = shellquote($wrapper_path, 'ipa-getkeytab', '-p', $keytab_principal, '-k', $keytab_path)
  exec { "ipa_service_keytab_${title}":
    command     => "umask 077 && ${getkeytab_command}",
    creates     => $keytab_path,
    require     => Exec["ipa_register_service_${title}"],
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
  }

  file { $keytab_path:
    ensure  => file,
    owner   => $owner,
    group   => $group,
    mode    => $mode,
    require => Exec["ipa_service_keytab_${title}"],
  }
}
