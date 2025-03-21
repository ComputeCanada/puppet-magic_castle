Puppet::Functions.create_function(:'profile::utils::split_options') do
    dispatch :split_options do
        param 'String', :options
        return_type 'Array'
    end
    def split_options(options)
        return options.scan(/(\w+=".*?"|[\w-]+)/).flatten
    end
end