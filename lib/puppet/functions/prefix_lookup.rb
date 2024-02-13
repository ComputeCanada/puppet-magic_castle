require 'yaml'

Puppet::Functions.create_function(:prefix_lookup) do
  dispatch :prefix_lookup do
    param 'Hash', :options
    param 'Puppet::LookupContext', :context
  end

  def prefix_lookup(options, context)
    path = options['path']
    node_prefix = options['node_prefix']
    data = context.cached_file_data(path) do |content|
      begin
        Puppet::Util::Yaml.safe_load(content, [Symbol], path)
      end
    end
    return data[node_prefix] || {}
  end
end
