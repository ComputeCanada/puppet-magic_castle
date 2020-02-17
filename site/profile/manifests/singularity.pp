class profile::singularity {

  yumrepo { 'singularity-copr-repo':
    enabled             => true,
    descr               => 'Copr repo for Singularity owned by cmdntrf',
    baseurl             => 'https://copr-be.cloud.fedoraproject.org/results/cmdntrf/singularity/epel-7-$basearch/',
    skip_if_unavailable => true,
    gpgcheck            => 1,
    gpgkey              => 'https://copr-be.cloud.fedoraproject.org/results/cmdntrf/singularity/pubkey.gpg',
    repo_gpgcheck       => 0,
  }

  # EPEL also provides singularity, but it is installed in /usr/bin.
  # We disable all repo except our own singularity repo for the duration
  # of the install.
  package { 'singularity':
    ensure          => 'installed',
    require         => Yumrepo['singularity-copr-repo'],
    install_options => [
      { '--disablerepo' => 'epel' },
      { '--enablerepo'  => 'singularity-copr-repo' }],
  }

  exec { 'singularity-symlink':
    command => 'ln -sf /opt/software/singularity-* /opt/software/singularity',
    creates => '/opt/software/singularity',
    require => Package['singularity'],
    path    => ['/usr/bin', '/bin']
  }
}
