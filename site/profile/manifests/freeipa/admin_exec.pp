# Run a command with IPA administrator credentials; pass guards through unchanged.
# Commands are shell strings; quote individual arguments with shellquote().
# Each command gets a separate, temporary Kerberos credential cache.
define profile::freeipa::admin_exec (
  String[1] $command,
  Array[String[1]] $environment = [],
  Optional[Variant[String[1], Array[String[1]]]] $creates = undef,
  Optional[Variant[String[1], Array[String[1]]]] $unless = undef,
  Optional[Variant[String[1], Array[String[1]]]] $onlyif = undef,
  Boolean $refreshonly = false,
  Numeric $timeout = 300,
  Array[String[1]] $path = ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
  Variant[Boolean, Enum['on_failure']] $logoutput = 'on_failure',
) {
  $wrapper_path = '/usr/local/bin/kinit_wrapper'
  ensure_resource ( 'file',
    'kinit_wrapper',
    {
      'path'   => $wrapper_path,
      'source' => 'puppet:///modules/profile/freeipa/kinit_wrapper',
      'mode'   => '0755',
    },
  )

  $ipa_passwd = lookup('profile::freeipa::server::admin_password')

  exec { $title:
    command     => shellquote($wrapper_path, '/bin/sh', '-c', $command),
    environment => $environment + ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    creates     => $creates,
    unless      => $unless,
    onlyif      => $onlyif,
    refreshonly => $refreshonly,
    timeout     => $timeout,
    path        => $path,
    logoutput   => $logoutput,
    require     => File['kinit_wrapper'],
  }
}
