class profile::additionalsoftware (
  Array[String] $packages,
) {
  include epel

  package { $packages:
    ensure  => 'installed',
    require => [
      Yumrepo['epel'],
    ],
  }
}
