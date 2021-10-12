require 'resolv'

Facter.add("nameservers") do
  setcode do
    Resolv::DNS::Config.default_config_hash[:nameserver]
  end
end