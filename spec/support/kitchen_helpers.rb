# frozen_string_literal: true

require "fileutils"
require "stringio"
require "tmpdir"

require "kitchen/driver/dummy"
require "kitchen/transport/dummy"
require "kitchen/verifier/dummy"

# Helpers for exercising {Kitchen::Provisioner::Dsc} against a genuine
# {Kitchen::Instance}.
#
# The provisioner reads most of its behaviour out of `config`, and Test Kitchen
# populates `config` in two passes: static `default_config` values, then lazy
# `default_config` blocks that are only evaluated once an instance is attached
# (`Kitchen::Provisioner::Dsc` uses one to derive `:configuration_name` from the
# suite name). Building a real instance with the stock dummy driver, transport
# and verifier gets both passes for free; a hand-rolled double would silently
# skip the second.
module KitchenHelpers
  # Default `:root_path` used by the specs. Test Kitchen's Windows default,
  # spelled out here so expectations can refer to it by name.
  DEFAULT_ROOT_PATH = 'C:\\kitchen'

  # Name of the suite the built instance runs. Override with `let(:suite_name)`
  # to exercise the `:configuration_name` default, which is derived from it.
  #
  # @return [String] the suite name
  def suite_name
    "default"
  end

  # Name of the platform the built instance runs. Anything starting with `win`
  # gives the instance a `powershell` shell type; override with
  # `let(:platform_name)` to test the bourne path.
  #
  # @return [String] the platform name
  def platform_name
    "windows-2022"
  end

  # Builds a provisioner wired to a real instance.
  #
  # @param config [Hash] provisioner configuration, merged over the defaults
  # @return [Kitchen::Provisioner::Dsc] a finalized provisioner
  def build_provisioner(config = {})
    defaults = { kitchen_root:, root_path: DEFAULT_ROOT_PATH }
    provisioner = Kitchen::Provisioner::Dsc.new(defaults.merge(config))
    build_instance(provisioner)
    provisioner
  end

  # Builds the {Kitchen::Instance} that owns +provisioner+.
  #
  # Constructing the instance is what calls `Provisioner#finalize_config!`, so
  # this is also what exercises the provisioner's LCM configuration merge.
  #
  # @param provisioner [Kitchen::Provisioner::Base] the provisioner under test
  # @return [Kitchen::Instance] the built instance
  def build_instance(provisioner)
    state_file = Kitchen::StateFile.new(kitchen_root, "#{suite_name}-#{platform_name}")

    Kitchen::Instance.new(
      suite: Kitchen::Suite.new(name: suite_name),
      platform: Kitchen::Platform.new(name: platform_name),
      driver: Kitchen::Driver::Dummy.new,
      provisioner:,
      transport: Kitchen::Transport::Dummy.new,
      verifier: Kitchen::Verifier::Dummy.new,
      lifecycle_hooks: Kitchen::LifecycleHooks.new({}, state_file),
      state_file:,
      logger: kitchen_logger
    )
  end

  # Creates the provisioner's sandbox and registers it for cleanup.
  #
  # {Kitchen::Provisioner::Base#create_sandbox} mints its own temporary
  # directory, so it has to be tracked separately from {#kitchen_root}.
  #
  # @param provisioner [Kitchen::Provisioner::Dsc] the provisioner under test
  # @return [String] absolute path to the created sandbox
  def create_sandbox_for(provisioner)
    provisioner.create_sandbox
    register_tmpdir(provisioner.sandbox_path)
  end

  # The temporary directory standing in for the user's cookbook/module root.
  #
  # @return [String] absolute path to the kitchen root
  def kitchen_root
    @kitchen_root ||= register_tmpdir(Dir.mktmpdir("kitchen-dsc-root-"))
  end

  # Everything the provisioner has logged during the current example.
  #
  # @return [String] captured log output
  def kitchen_log
    log_device.string
  end

  # @return [Kitchen::Logger] a debug-level logger writing to {#log_device}
  def kitchen_logger
    @kitchen_logger ||= Kitchen::Logger.new(stdout: log_device, level: :debug)
  end

  # Writes a file beneath {#kitchen_root}, creating parent directories.
  #
  # @param relative_path [String] path relative to the kitchen root
  # @param content [String] file contents
  # @return [String] the absolute path written
  def write_kitchen_file(relative_path, content = "# fixture\n")
    path = File.join(kitchen_root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  # Lists every file under +dir+ as paths relative to it.
  #
  # @param dir [String] directory to walk
  # @return [Array<String>] sorted relative paths of regular files
  def files_under(dir)
    Dir.glob(File.join(dir, "**/*"), File::FNM_DOTMATCH)
      .reject { |path| File.directory?(path) }
      .map { |path| path.sub("#{dir}/", "") }
      .sort
  end

  # Registers a directory for removal at the end of the example.
  #
  # @param path [String] directory to remove later
  # @return [String] +path+, for chaining
  def register_tmpdir(path)
    kitchen_tmpdirs << path
    path
  end

  # Removes every directory registered during the example.
  #
  # @return [void]
  def cleanup_kitchen_tmpdirs
    kitchen_tmpdirs.each { |path| FileUtils.remove_entry(path, true) }
    kitchen_tmpdirs.clear
  end

  private

  # @return [StringIO] backing device for {#kitchen_logger}
  def log_device
    @log_device ||= StringIO.new
  end

  # @return [Array<String>] directories to clean up after the example
  def kitchen_tmpdirs
    @kitchen_tmpdirs ||= []
  end
end
