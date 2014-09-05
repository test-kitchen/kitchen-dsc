# encoding: utf-8

$:.unshift File.expand_path('../lib', __FILE__)
require 'kitchen-dsc/version'

Gem::Specification.new do |s|
  s.name          = "kitchen-puppet"
  s.version       = Kitchen::Dsc::VERSION
  s.authors       = ["Steven Murawski"]
  s.email         = ["steven.murawski@gmail.com"]
  s.homepage      = "https://github.com/smurawski/kitchen-dsc"
  s.summary       = "PowerShell DSC provisioner for test-kitchen"
  candidates = Dir.glob("{lib,support}/**/*") +  ['README.md', 'provisioner_options.md', 'kitchen-dsc.gemspec']
  s.files = candidates.sort
  s.platform      = Gem::Platform::RUBY
  s.require_paths = ['lib']
  s.rubyforge_project = '[none]'
  s.description = <<-EOF
== DESCRIPTION:

DSC Provisioner for Test Kitchen

== FEATURES:

Supports ?

EOF

end
