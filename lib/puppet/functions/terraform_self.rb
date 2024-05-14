require 'yaml'

Puppet::Functions.create_function(:terraform_self) do
  dispatch :terraform_self do
    param 'Hash', :options
    param 'Puppet::LookupContext', :context
  end

  def terraform_self(options, context)
    path = options['path']
    hostname = options['hostname']
    data = context.cached_file_data(path) do |content|
      begin
        Puppet::Util::Yaml.safe_load(content, [Symbol], path)
      end
    end
    return { 'terraform' => { 'self' => data['terraform']['instances'][hostname] || {} } }
  end
end