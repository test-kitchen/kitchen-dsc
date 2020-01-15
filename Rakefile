require "bundler/gem_tasks"

require "rake/testtask"
Rake::TestTask.new(:unit) do |t|
  t.libs.push "lib"
  t.test_files = FileList["spec/**/*_spec.rb"]
  t.verbose = true
end

require "rubocop/rake_task"
require "chefstyle"

desc "Run RuboCop on the lib directory"
RuboCop::RakeTask.new(:rubocop) do |task|
  task.patterns = ["lib/**/*.rb"]
  # don't abort rake on failure
  task.fail_on_error = false
end

desc "Run all test suites"
task test: [:unit, :rubocop]

task default: [:test]

begin
  require "github_changelog_generator/task"
  require "kitchen-dsc/version"

  GitHubChangelogGenerator::RakeTask.new :changelog do |config|
    config.future_release = "v#{Kitchen::Dsc::VERSION}"
    config.issues = false
    config.pulls = true
    config.user = "test-kitchen"
    config.project = "kitchen-dsc"
  end
rescue LoadError
  puts "github_changelog_generator is not available. " \
    "gem install github_changelog_generator to generate changelogs"
end
