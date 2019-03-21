class profile::singularity {
  $singularity_version = "3.1"

  yumrepo { 'singularity-copr-repo':
    enabled             => 'true',
    descr               => 'Copr repo for Singularity owned by cmdntrf',
    baseurl             => 'https://copr-be.cloud.fedoraproject.org/results/cmdntrf/singularity/epel-7-$basearch/',
    skip_if_unavailable => 'true',
    gpgcheck            => 1,
    gpgkey              => 'https://copr-be.cloud.fedoraproject.org/results/cmdntrf/singularity/pubkey.gpg',
    repo_gpgcheck       => 0,
  }

  package { 'singularity':
    ensure  => 'installed',
    require => Yumrepo['singularity-copr-repo']
  }

  file { '/opt/software/singularity':
    ensure => 'link',
    target => "/opt/software/singularity-$singularity_version"
  }
}
