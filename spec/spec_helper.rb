# frozen_string_literal: true

#
# Copyright (C) 2014 Steven Murawski
#
# Licensed under the Apache 2 License.
# See LICENSE for more details

# Coverage must be started before any library code is loaded, otherwise methods
# defined at require-time are recorded as uncovered. Set COVERAGE=false to skip
# it (useful when bisecting or profiling a single spec file).
unless ENV["COVERAGE"] == "false"
  require "simplecov"

  SimpleCov.start do
    enable_coverage :branch
    add_filter "/spec/"
    track_files "lib/**/*.rb"
    # Deliberately no `minimum_coverage`: coverage is a diagnostic here, not a
    # gate. CI must never fail because a percentage moved.
  end
end

require "kitchen"
require "kitchen/provisioner/dsc"
require "kitchen-dsc/version"

require "stringio"
require "tmpdir"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |file| require file }

RSpec.configure do |config|
  config.include KitchenHelpers

  # rspec-expectations
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
    # The provisioner emits multi-kilobyte PowerShell scripts; truncating the
    # diff on failure hides the one line that actually differs.
    expectations.max_formatted_output_length = nil
  end

  # rspec-mocks
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.raise_errors_for_deprecations!

  config.default_formatter = "doc" if config.files_to_run.one?

  config.order = :random
  Kernel.srand config.seed

  # Ruby warnings are opt-in: test-kitchen and its transitive dependencies emit
  # enough of their own to drown out anything this gem causes.
  config.warnings = ENV["RSPEC_WARNINGS"] == "true"

  # Keep Test Kitchen's global logger out of the spec output. Individual
  # examples get their own logger via KitchenHelpers#kitchen_log.
  config.before(:suite) do
    Kitchen.logger = Kitchen::Logger.new(stdout: StringIO.new, level: :debug)
  end

  config.after do
    cleanup_kitchen_tmpdirs
  end
end
