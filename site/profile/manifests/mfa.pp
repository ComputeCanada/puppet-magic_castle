# MFA class which allows for multiple MFA implementations to
# be deployed in one cluster deployment.
class profile::mfa::duo::login {
  if $profile::mfa::duo::login {
    include duo_unix
  }
}

class profile::mfa::duo::mgmt {
  if $profile::mfa::duo::mgmt {
    include duo_unix
  }
}

class profile::mfa::duo::node {
  if $profile::mfa::duo::node {
    include duo_unix
  }
}
