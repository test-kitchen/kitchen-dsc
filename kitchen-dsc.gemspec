# encoding: utf-8

$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
require 'kitchen-dsc/version'

Gem::Specification.new do |s|
  s.name              = 'kitchen-dsc'
  s.version           = Kitchen::Dsc::VERSION
  s.authors           = ['Steven Murawski']
  s.email             = ['steven.murawski@gmail.com']
  s.homepage          = 'https://github.com/smurawski/kitchen-dsc'
  s.summary           = 'PowerShell DSC provisioner for test-kitchen'
  candidates          = Dir.glob('{lib,support}/**/*') +  ['README.md', 'kitchen-dsc.gemspec']
  s.files             = candidates.sort
  s.platform          = Gem::Platform::RUBY
  s.require_paths     = ['lib']
  s.rubyforge_project = '[none]'
  s.license           = 'MIT'
  s.description       = <<-EOF
== DESCRIPTION:

DSC Provisioner for Test Kitchen

== FEATURES:

TBD

EOF

end
