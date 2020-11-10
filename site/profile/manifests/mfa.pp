# MFA class which allows for multiple MFA implementations to
# be deployed in one cluster deployment.
class profile::mfa::duo::login {
  if lookup(profile::mfa::duo::login) {
    include duo_unix
  }
}

class profile::mfa::duo::mgmt {
  if lookup(profile::mfa::duo::mgmt) {
    include duo_unix
  }
}

class profile::mfa::duo::node {
  if lookup(profile::mfa::duo::node) {
    include duo_unix
  }
}
