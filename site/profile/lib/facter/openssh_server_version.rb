Facter.add(:openssh_server_version) do
  setcode do
    # Executes ssh -V and parses the version string
    version_output = Facter::Core::Execution.execute('sshd -V 2>&1')
    if version_output =~ /OpenSSH_([\d.]+)/
      $1
    else
      nil
    end
  end
end