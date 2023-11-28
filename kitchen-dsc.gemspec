lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "kitchen-dsc/version"

Gem::Specification.new do |gem|
  gem.name              = "kitchen-dsc"
  gem.version           = Kitchen::Dsc::VERSION
  gem.authors           = ["Test Kitchen Team"]
  gem.email             = ["help@sous-chefs.org"]
  gem.homepage          = "https://github.com/test-kitchen/kitchen-dsc"
  gem.summary           = "PowerShell DSC provisioner for test-kitchen"
  gem.description       = "PowerShell DSC provisioner for test-kitchen"
  gem.files              = `git ls-files`.split($/)
  gem.test_files         = gem.files.grep(%r{^(test|spec|features)/})
  gem.platform          = Gem::Platform::RUBY
  gem.require_paths     = ["lib"]
  gem.license           = "Apache-2.0"

  gem.add_dependency    "dsc_lcm_configuration"
  gem.add_dependency    "test-kitchen", ">= 1.9"
end
