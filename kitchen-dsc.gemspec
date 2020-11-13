$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require "kitchen-dsc/version"

Gem::Specification.new do |s|
  s.name              = "kitchen-dsc"
  s.version           = Kitchen::Dsc::VERSION
  s.authors           = ["Steven Murawski"]
  s.email             = ["smurawski@chef.io"]
  s.homepage          = "https://github.com/test-kitchen/kitchen-dsc"
  s.summary           = "PowerShell DSC provisioner for test-kitchen"
  s.description       = "PowerShell DSC provisioner for test-kitchen"
  candidates          = Dir.glob("lib/**/*") + ["README.md", "kitchen-dsc.gemspec"]
  s.files             = candidates.sort
  s.platform          = Gem::Platform::RUBY
  s.require_paths     = ["lib"]
  s.license           = "Apache-2.0"
  s.add_dependency "test-kitchen", ">= 1.9"
  s.add_dependency "dsc_lcm_configuration"

  s.add_development_dependency "countloc", "~> 0.4"
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec",     "~> 3.2"
  s.add_development_dependency "simplecov", "~> 0.9"
  s.add_development_dependency "minitest",  "~> 5.3"
  s.add_development_dependency "yard",      "~> 0.8"
  s.add_development_dependency "pry"
  s.add_development_dependency "pry-stack_explorer"
  s.add_development_dependency "pry-byebug"
  s.add_development_dependency "rb-readline"

  # style and complexity libraries are tightly version pinned as newer releases
  # may introduce new and undesireable style choices which would be immediately
  # enforced in CI
  s.add_development_dependency "chefstyle", "1.5.1"
  s.add_development_dependency "cane", "3.0.0"
end
