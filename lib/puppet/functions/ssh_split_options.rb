Puppet::Functions.create_function(:ssh_split_options) do
    dispatch :ssh_split_options do
        param 'String', :options
        return_type 'Array'
    end
    def ssh_split_options(options)
        return options.scan(/(\w+=".*?"|[\w-]+)/).flatten
    end
end