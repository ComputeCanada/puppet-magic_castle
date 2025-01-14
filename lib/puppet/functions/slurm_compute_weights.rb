Puppet::Functions.create_function(:slurm_compute_weights) do
    dispatch :slurm_compute_weights do
        param 'Hash', :instances
        return_type 'Hash'
    end

    def slurm_compute_weights(instances)
        require 'set'
        unique_specs = Set.new(instances.values.map {|i| i['specs']})
        sorted_specs = unique_specs.sort_by{|spec| [spec['gpus'], spec['ram'], spec['cpus']]}
        weights = Hash.new
        for i in 0..sorted_specs.size-1
            weights[sorted_specs[i]] = i+1
        end
        weights_per_node = Hash.new
        for inst in instances
            if inst[1].key?("weight") and inst[1]['weight'].is_a? Numeric then
                weights_per_node[inst[0]] = inst[1]['weight']
            else
                weights_per_node[inst[0]] = weights[inst[1]['specs']]
            end
        end
        return weights_per_node
      end
end