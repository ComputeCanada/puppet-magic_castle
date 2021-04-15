# MFA class which allows for multiple MFA implementations to
# be deployed in one cluster deployment.
class profile::mfa ( Enum['none', 'duo'] $provider ) {
  if ($provider == 'duo') {
    include duo_unix
  }
}
