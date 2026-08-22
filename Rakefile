# frozen_string_literal: true

require "bundler/gem_tasks"

require "cookstyle/chefstyle"
require "rubocop/rake_task"

RuboCop::RakeTask.new(:style) do |task|
  task.options += ["--display-cop-names", "--no-color"]
end

require "rspec/core/rake_task"

# Named `test` because the shared test-kitchen CI workflow invokes
# `bundle exec rake test`. Renaming it would break CI.
RSpec::Core::RakeTask.new(:test, :tag) do |t, args|
  t.rspec_opts = [].tap do |a|
    a << "--format #{ENV["CI"] ? "documentation" : "progress"}"
    a << "--backtrace" if ENV["VERBOSE"] || ENV["DEBUG"]
    a << "--seed #{ENV["SEED"]}" if ENV["SEED"]
    a << "--tag #{args[:tag]}" if args[:tag]
    a << "--only-failures" if ENV["ONLY_FAILURES"]
  end.join(" ")
end

# YARD lives in the :development bundle group, which a test-only install may
# skip. Documentation tasks are optional, so degrade rather than break `rake`.
begin
  require "yard"

  YARD::Rake::YardocTask.new(:yard) do |t|
    t.stats_options = ["--list-undoc"]
  end

  namespace :yard do
    desc "Report documentation coverage, listing undocumented objects"
    task :stats do
      sh "yard stats --list-undoc"
    end

    desc "Serve the docs at http://localhost:8808, reloading on change"
    task :server do
      sh "yard server --reload"
    end
  end
rescue LoadError
  %w{yard yard:stats yard:server}.each do |name|
    desc "(unavailable: install the :development bundle group)" if name == "yard"
    task name do
      abort "YARD is not available. Run `bundle install --with development`."
    end
  end
end

desc "Run the linter and the unit tests"
task default: %i{style test}
