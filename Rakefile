require "bundler/gem_tasks"
require "chefstyle"
require "rubocop/rake_task"

RuboCop::RakeTask.new(:style) do |task|
  task.options += ["--display-cop-names", "--no-color"]
end

# Create the spec task.
require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:test, :tag) do |t, args|
  t.rspec_opts = [].tap do |a|
    a << "--color"
    a << "--format #{ENV["CI"] ? "documentation" : "progress"}"
    a << "--backtrace" if ENV["VERBOSE"] || ENV["DEBUG"]
    a << "--seed #{ENV["SEED"]}" if ENV["SEED"]
    a << "--tag #{args[:tag]}" if args[:tag]
    a << "--default-path test"
    a << "-I test/spec"
  end.join(" ")
end
