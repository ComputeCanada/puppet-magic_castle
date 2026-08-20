require 'puppetlabs_spec_helper/module_spec_helper'
require 'rspec-puppet-facts'

include RspecPuppetFacts

RSpec.configure do |c|
  c.default_facts = {
    :os => { 'release' => { 'major' => '8' } },
    :cloud => { 'provider' => 'aws' },
    :virtual => 'kvm'
  }
end
