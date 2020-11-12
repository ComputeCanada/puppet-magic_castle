# MFA class which allows for multiple MFA implementations to
# be deployed in one cluster deployment.
class profile::mfa::login ( Enum['none', 'duo'] $provider ) {
  if ($provider == 'duo') {
    include duo_unix
  }
}

class profile::mfa::mgmt ( Enum['none', 'duo'] $provider ) {
  if ($provider == 'duo') {
    include duo_unix
  }
}

class profile::mfa::node ( Enum['none', 'duo'] $provider ) {
  if ($provider == 'duo') {
    include duo_unix
  }
}
