# frozen_string_literal: true

require 'puppet'
require 'fileutils'

SEPARATOR = [Regexp.escape(File::SEPARATOR.to_s), Regexp.escape(File::ALT_SEPARATOR.to_s)].join

Puppet::Reports.register_report(:store_latest) do
  desc "Store the yaml report on disk.  Each host sends its report as a YAML dump
    and this just stores the file on disk, in the `reportdir` directory.

    Only keep the latest available."

  def process
    validate_host(host)

    dir = File.join(Puppet[:reportdir], host)

    unless Puppet::FileSystem.exist?(dir)
      FileUtils.mkdir_p(dir)
      FileUtils.chmod_R(0o750, dir)
    end

    # Now store the report.
    name =  "latest.yaml"

    file = File.join(dir, name)

    begin
      Puppet::FileSystem.replace_file(file, 0o640) do |fh|
        fh.print to_yaml
      end
    rescue => detail
      Puppet.log_exception(detail, "Could not write report for #{host} at #{file}: #{detail}")
    end

    # Only testing cares about the return value
    file
  end

  # removes all reports for a given host?
  def self.destroy(host)
    validate_host(host)

    dir = File.join(Puppet[:reportdir], host)

    if Puppet::FileSystem.exist?(dir)
      Dir.entries(dir).each do |file|
        next if ['.', '..'].include?(file)

        file = File.join(dir, file)
        Puppet::FileSystem.unlink(file) if File.file?(file)
      end
      Dir.rmdir(dir)
    end
  end

  def validate_host(host)
    if host =~ Regexp.union(/[#{SEPARATOR}]/, /\A\.\.?\Z/)
      raise ArgumentError, _("Invalid node name %{host}") % { host: host.inspect }
    end
  end
  module_function :validate_host
end