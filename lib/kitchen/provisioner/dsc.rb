# frozen_string_literal: true

#
# Author:: Steven Murawski (<steven.murawski@gmail.com>)
#
# Copyright (C) 2014 Steven Murawski
#
# Licensed under the Apache 2 License.
# See LICENSE for more details

require "fileutils" unless defined?(FileUtils)
require "pathname" unless defined?(Pathname)
require "kitchen/provisioner/base"
require "kitchen/util"
require "dsc_lcm_configuration"

module Kitchen
  # Test Kitchen's provisioner namespace, reopened to register the DSC
  # provisioner alongside the ones that ship with Test Kitchen itself.
  module Provisioner
    # Applies PowerShell Desired State Configuration to a Test Kitchen instance.
    #
    # The provisioner runs across the four Test Kitchen phases:
    #
    # 1. {#install_command} configures the Local Configuration Manager on the
    #    system under test.
    # 2. {#init_command} creates the remote configuration directory and, on
    #    WMF 5, installs any modules requested from a PowerShell gallery.
    # 3. {#create_sandbox} stages DSC resources and the configuration script on
    #    the workstation, ready for upload.
    # 4. {#prepare_command} compiles the configuration into a MOF on the system
    #    under test and {#run_command} applies it.
    #
    # Two project layouts are supported, chosen automatically by
    # {#powershell_module?}: *module style*, where the kitchen root is itself a
    # PowerShell module (identified by a `<module name>.psd1` manifest), and
    # *repository style*, where DSC resources live in a `modules` directory.
    #
    # @example Minimal kitchen.yml
    #   provisioner:
    #     name: dsc
    #     dsc_local_configuration_manager_version: wmf5
    #     configuration_script: web.ps1
    #
    # @see https://github.com/test-kitchen/kitchen-dsc kitchen-dsc README
    class Dsc < Base
      kitchen_provisioner_api_version 2

      # @!attribute [rw] tmp_dir
      #   @return [String, nil] path to a scratch directory on the system under
      #     test. Set by consumers that need somewhere to write intermediate
      #     files; unused by the provisioner itself.
      attr_accessor :tmp_dir

      # @!method tmp_dir=(value)
      #   Points the provisioner at a scratch directory on the system under
      #   test.
      #
      #   @param value [String, nil] the path to record, or nil to clear it
      #   @return [String, nil] +value+

      default_config :modules_path, "modules"

      default_config :configuration_script_folder, "examples"
      default_config :configuration_script, "dsc_configuration.ps1"
      default_config :configuration_name do |provisioner|
        [provisioner.instance.suite.name]
      end

      default_config :configuration_data_variable, "ConfigurationData"

      default_config :nuget_force_bootstrap, true
      default_config :gallery_uri
      default_config :gallery_name
      default_config :modules_from_gallery

      default_config :dsc_local_configuration_manager_version, "wmf4"
      default_config :dsc_local_configuration_manager, {}

      # Resolves the Local Configuration Manager settings before the instance is
      # used.
      #
      # Replaces the caller's partial `:dsc_local_configuration_manager` hash
      # with the fully defaulted settings for the configured WMF version, so
      # later phases and `kitchen diagnose` see the values that will actually be
      # applied.
      #
      # @param instance [Kitchen::Instance] the instance this provisioner serves
      # @return [self]
      def finalize_config!(instance)
        config[:dsc_local_configuration_manager] = lcm.lcm_config
        super(instance)
      end

      # Builds the command that configures the Local Configuration Manager.
      #
      # Runs during Test Kitchen's `install` phase, before any configuration is
      # compiled, since the LCM controls how DSC behaves for the rest of the
      # run.
      #
      # @return [String] PowerShell that declares and applies the `SetupLCM`
      #   meta-configuration
      def install_command
        full_lcm_configuration_script = <<-EOH
        #{lcm.lcm_configuration_script}

        $null = SetupLCM
        Set-DscLocalConfigurationManager -Path ./SetupLCM | out-null
        EOH

        wrap_powershell_code(full_lcm_configuration_script)
      end

      # Builds the command that prepares the system under test for upload.
      #
      # Always creates the directory the configuration script will be copied
      # into. On WMF 5 with `:modules_from_gallery` set, it also bootstraps
      # PackageManagement and installs those modules.
      #
      # @return [String] PowerShell run during the `converge` phase, before
      #   files are transferred
      def init_command
        script = <<~EOH
          #{setup_config_directory_script}
          #{install_module_script if install_modules?}
        EOH
        wrap_powershell_code(script)
      end

      # Stages DSC resources and the configuration script into the sandbox.
      #
      # The sandbox is the local directory Test Kitchen uploads to the system
      # under test. Which staging strategy runs depends on whether the project
      # is laid out as a PowerShell module or as a repository of modules.
      #
      # @return [void]
      # @raise [Errno::ENOENT] if the configuration script named by
      #   `:configuration_script_folder` and `:configuration_script` is missing
      # @see #prepare_resource_style_directory
      # @see #prepare_repo_style_directory
      def create_sandbox
        super
        info("Staging DSC Resource Modules for copy to the SUT")
        if powershell_module?
          prepare_resource_style_directory
        else
          prepare_repo_style_directory
        end
        info("Staging DSC configuration script for copy to the SUT")
        prepare_configuration_script
      end

      # Builds the command that compiles configurations into MOF documents.
      #
      # Copies the uploaded modules onto the `PSModulePath`, loads the
      # configuration script, then compiles each name in `:configuration_name`
      # into `c:/configurations/<name>`. Any leftover MOF from a previous
      # converge is removed first so a failed compile cannot be silently applied.
      #
      # @return [String] PowerShell run after files are transferred and before
      #   {#run_command}
      def prepare_command
        info("Moving DSC Resources onto PSModulePath")
        # +@ makes an explicitly mutable buffer under frozen_string_literal.
        scripts = +<<-EOH

        if (Test-Path (join-path #{config[:root_path]} 'modules'))
        {
          dir ( join-path #{config[:root_path]} 'modules/*') -directory |
          copy-item -destination $env:programfiles/windowspowershell/modules/ -recurse -force
        }

        $ConfigurationScriptPath = Join-path #{config[:root_path]} #{sandboxed_configuration_script}
        if (-not (test-path $ConfigurationScriptPath))
        {
          throw "Failed to find $ConfigurationScriptPath"
        }
        invoke-expression (get-content $ConfigurationScriptPath -raw)

        EOH
        ensure_array(config[:configuration_name]).each do |configuration|
          info("Generating the MOF script for the configuration #{configuration}")
          stage_resources_and_generate_mof_script = <<-EOH

            if(Test-Path c:/configurations/#{configuration})
            {
                Remove-Item -Recurse -Force c:/configurations/#{configuration}
            }

            $Error.clear()

            if (-not (test-path 'c:/configurations'))
            {
              mkdir 'c:/configurations' | out-null
            }

            if (-not (get-command #{configuration}))
            {
              throw "Failed to create a configuration command #{configuration}"
            }

            #{configuration_data_assignment unless config[:configuration_data].nil?}

            try{
              $null = #{configuration} -outputpath c:/configurations/#{configuration} #{"-configurationdata $" + configuration_data_variable}
            }
            catch{
            }

            if($Error -ne $null)
            {
              $Error[-1]
              exit 1
            }

          EOH
          scripts << stage_resources_and_generate_mof_script
        end
        debug("Shelling out: #{scripts}")
        wrap_powershell_code(scripts)
      end

      # Builds the command that applies the compiled MOF documents.
      #
      # A DSC resource may require a reboot to finish. Rather than failing, the
      # generated script reboots the node and exits 35, and this method opts the
      # instance into retrying that exit code so the converge resumes once the
      # node is back. A `:retry_on_exit_code` list the caller already populated
      # is left untouched.
      #
      # `:max_retries` is only left alone when it differs from Test Kitchen's
      # default of `1`, which an explicit `max_retries: 1` does not: that
      # setting is indistinguishable from the default and is raised to `3`.
      #
      # @return [String] PowerShell that starts a DSC configuration job per
      #   configuration name and reports its errors
      def run_command
        config[:retry_on_exit_code] = [35] if config[:retry_on_exit_code].empty?
        config[:max_retries] = 3 if config[:max_retries] == 1
        scripts = +""
        ensure_array(config[:configuration_name]).each do |configuration|
          info("Running the configuration #{configuration}")
          run_configuration_script = <<-EOH
            $job = start-dscconfiguration -Path c:/configurations/#{configuration} -force
            $job | wait-job
            $verbose_output = $job.childjobs[0].verbose
            $verbose_output
            if ($verbose_output -match 'A reboot is required to progress further. Please reboot the system.') {
              "A reboot is required to continue."
              shutdown /r /t 15
              exit 35
            }
            $dsc_errors = $job.childjobs[0].Error
            if ($dsc_errors -ne $null) {
              $dsc_errors
              exit 1
            }
          EOH
          scripts << run_configuration_script
        end
        debug("Shelling out: #{scripts}")
        wrap_powershell_code(scripts)
      end

      private

      # The Local Configuration Manager configuration for the target WMF version.
      #
      # Note that `DscLcmConfiguration::Factory` only recognizes `"4"`,
      # `"wmf4_with_update"`, `"5"` and `"wmf5"`; every other value, including
      # this provisioner's own `"wmf4"` default, yields the base LCM
      # configuration.
      #
      # @api private
      # @return [DscLcmConfiguration::LcmBase] a memoized LCM configuration
      def lcm
        @lcm ||= begin
          lcm_version = config[:dsc_local_configuration_manager_version]
          lcm_config = config[:dsc_local_configuration_manager]
          DscLcmConfiguration::Factory.create(lcm_version, lcm_config)
        end
      end

      # PowerShell that creates the remote directory holding the configuration
      # script.
      #
      # @api private
      # @return [String] a `mkdir` invocation
      def setup_config_directory_script
        "mkdir (split-path (join-path #{config[:root_path]} #{sandboxed_configuration_script})) -force | out-null"
      end

      # Renders a module specification hash as `install-module` parameters.
      #
      # A `Force` key is dropped because `-force` is already appended to every
      # `install-module` call, and PowerShell rejects a duplicated parameter. A
      # `Repository` key is added from the configured gallery unless the caller
      # supplied one.
      #
      # Values are interpolated as written, without quoting, so a value
      # containing a space reaches PowerShell as two arguments.
      #
      # @api private
      # @param module_specification_hash [Hash] `install-module` parameters, as
      #   given in kitchen.yml
      # @return [String] space-separated `-Key Value` pairs
      def powershell_module_params(module_specification_hash)
        # Work on a copy: this hash is the caller's own entry in
        # config[:modules_from_gallery], and writing a :repository key back
        # into it would leave `kitchen diagnose` reporting settings the user
        # never wrote.
        params = module_specification_hash.reject { |key, _| key.to_s.casecmp?("force") }
        params[:repository] = psmodule_repository_name unless params.keys.any? { |key| key.to_s.casecmp?("repository") }
        params.map { |key, value| "-#{key} #{value}" }.join(" ")
      end

      # Builds one `install-module` line per entry in `:modules_from_gallery`.
      #
      # Entries may be plain module names or hashes of `install-module`
      # parameters.
      #
      # @api private
      # @return [Array<String>] PowerShell `install-module` invocations
      def powershell_modules
        Array(config[:modules_from_gallery]).map do |powershell_module|
          params = if powershell_module.is_a? Hash
                     powershell_module_params(powershell_module)
                   else
                     "-name '#{powershell_module}' -Repository #{psmodule_repository_name}"
                   end
          "install-module #{params} -force | out-null"
        end
      end

      # PowerShell that bootstraps the NuGet package provider.
      #
      # PackageManagement cannot install from a gallery until the NuGet provider
      # is present, and its interactive bootstrap prompt would hang a converge.
      #
      # @api private
      # @return [String, nil] the bootstrap command, or nil when
      #   `:nuget_force_bootstrap` is disabled
      def nuget_force_bootstrap
        return unless config[:nuget_force_bootstrap]

        info("Bootstrapping the nuget package provider for PowerShell PackageManagement.")
        "install-packageprovider nuget -force -forcebootstrap | out-null"
      end

      # The PowerShellGet repository name to install modules from.
      #
      # @api private
      # @return [String] `:gallery_name` when set, the public `PSGallery` when
      #   neither gallery setting is given, and `testing` for an unnamed private
      #   `:gallery_uri`
      def psmodule_repository_name
        return "PSGallery" if config[:gallery_name].nil? && config[:gallery_uri].nil?
        return "testing"   if config[:gallery_name].nil?

        config[:gallery_name]
      end

      # PowerShell that registers a private gallery as a package source.
      #
      # Only `:gallery_uri` triggers registration. A `:gallery_name` on its own
      # names a source that must already be registered on the instance;
      # otherwise `install-module` fails with `Unable to find repository`.
      #
      # @api private
      # @return [String, nil] the `register-packagesource` command, or nil when
      #   no `:gallery_uri` is configured
      def register_psmodule_repository
        return if config[:gallery_uri].nil?

        info("Registering a new PowerShellGet Repository - #{psmodule_repository_name}")
        "register-packagesource -providername PowerShellGet -name '#{psmodule_repository_name}' -location '#{config[:gallery_uri]}' -force -trusted"
      end

      # PowerShell that installs every requested gallery module.
      #
      # @api private
      # @return [String, nil] the bootstrap, registration and install commands,
      #   or nil when no gallery modules are configured
      def install_module_script
        return if config[:modules_from_gallery].nil?

        <<-EOH
  #{nuget_force_bootstrap}
  #{register_psmodule_repository}
  #{powershell_modules.join("\n")}
        EOH
      end

      # Whether gallery modules should be installed during {#init_command}.
      #
      # Gallery installation depends on PowerShellGet, which ships with WMF 5.
      #
      # The version test is an exact string comparison against `"wmf5"`, which
      # is narrower than the set {#lcm} accepts: `"5"` also selects the WMF 5
      # LCM, but leaves this false. Whenever it is false `:modules_from_gallery`
      # is dropped from {#init_command} without a warning, and the converge
      # fails later on the missing DSC resource.
      #
      # @api private
      # @return [Boolean] true only when targeting WMF 5 with modules requested
      def install_modules?
        config[:dsc_local_configuration_manager_version] == "wmf5" &&
          !config[:modules_from_gallery].nil?
      end

      # Name of the PowerShell variable holding configuration data.
      #
      # @api private
      # @return [String] `:configuration_data_variable`, or `ConfigurationData`
      #   when it was explicitly blanked out
      def configuration_data_variable
        config[:configuration_data_variable].nil? ? "ConfigurationData" : config[:configuration_data_variable]
      end

      # PowerShell that assigns `:configuration_data` to its variable.
      #
      # @api private
      # @return [String] a hashtable assignment
      def configuration_data_assignment
        "$" + configuration_data_variable + " = " + ps_hash(config[:configuration_data])
      end

      # Wraps generated PowerShell for execution by the transport.
      #
      # Progress streams are silenced first: WinRM relays them as output, which
      # makes converge logs unreadable and can slow long-running resources.
      #
      # @api private
      # @param code [String] the PowerShell to wrap
      # @return [String] the wrapped command
      def wrap_powershell_code(code)
        wrap_shell_code(["$ProgressPreference = 'SilentlyContinue';", code].join("\n"))
      end

      # Whether the kitchen root is itself a PowerShell module.
      #
      # Detected by a `<module name>.psd1` manifest sitting beside the project,
      # which selects module-style staging over repository-style staging.
      #
      # {#module_name} is the basename of `:kitchen_root`, so the manifest has
      # to match the directory the project was cloned into rather than the
      # module's own name. Cloning into a differently named directory silently
      # falls back to repository style.
      #
      # @api private
      # @return [Boolean] true when a matching module manifest exists
      def powershell_module?
        module_metadata_file = File.join(config[:kitchen_root], "#{module_name}.psd1")
        File.exist?(module_metadata_file)
      end

      # Lists the files to stage from a module-style project.
      #
      # Directories are excluded because the copy recreates them as needed, and
      # repository housekeeping files are excluded because they are not part of
      # the module.
      #
      # @api private
      # @param path [String] directory to enumerate
      # @return [Array<String>] absolute paths of files to stage
      def list_files(path)
        base_directory_content = Dir.glob(File.join(path, "*"))
        nested_directory_content = Dir.glob(File.join(path, "*/**/*"))
        all_directory_content = [base_directory_content, nested_directory_content].flatten

        ignore_files = ["Gemfile", "Gemfile.lock", "README.md", "LICENSE.txt"]
        all_directory_content.reject do |f|
          debug("Enumerating #{f}")
          ignore_files.include?(File.basename(f)) || File.directory?(f)
        end
      end

      # The PowerShell module name implied by the project directory.
      #
      # @api private
      # @return [String] basename of `:kitchen_root`
      def module_name
        File.basename(config[:kitchen_root])
      end

      # Stages a module-style project into the sandbox.
      #
      # The whole kitchen root is copied to `modules/<module name>` so the
      # module lands on the system under test's `PSModulePath` under the name
      # DSC expects.
      #
      # @api private
      # @return [void]
      def prepare_resource_style_directory
        sandbox_base_module_path = File.join(sandbox_path, "modules/#{module_name}")

        base = config[:kitchen_root]
        list_files(base).each do |src|
          dest = File.join(sandbox_base_module_path, src.sub("#{base}/", ""))
          FileUtils.mkdir_p(File.dirname(dest))
          debug("Staging #{src} ")
          debug("  at #{dest}")
          FileUtils.cp(src, dest, preserve: true)
        end
      end

      # Stages a repository-style project into the sandbox.
      #
      # A missing modules directory is not an error: a project may ship only a
      # configuration script and rely on resources already present on the node.
      #
      # @api private
      # @return [void]
      def prepare_repo_style_directory
        module_path = File.join(config[:kitchen_root], config[:modules_path])
        sandbox_module_path = File.join(sandbox_path, "modules")

        if Dir.exist?(module_path)
          debug("Moving #{module_path} to #{sandbox_module_path}")
          FileUtils.cp_r(module_path, sandbox_module_path)
        else
          debug("The modules path #{module_path} was not found. Not moving to #{sandbox_module_path}.")
        end
      end

      # Path of the configuration script relative to the sandbox and to
      # `:root_path` on the system under test.
      #
      # @api private
      # @return [String] the sandboxed script path
      def sandboxed_configuration_script
        File.join("configuration", config[:configuration_script])
      end

      # Indentation used when rendering PowerShell hashtables.
      #
      # @api private
      # @param depth [Integer] number of spaces
      # @return [String] a run of spaces
      def pad(depth = 0)
        " " * depth
      end

      # Characters PowerShell treats specially inside a double-quoted string.
      #
      # A backtick starts an escape sequence, a dollar sign starts a variable
      # or subexpression, and a double quote ends the string.
      #
      # @api private
      PS_DOUBLE_QUOTE_SPECIAL_CHARS = /[`$"]/

      # Escapes a value for interpolation into a PowerShell double-quoted string.
      #
      # Without this, configuration data is silently corrupted: `P@$$w0rd`
      # reaches DSC as `P@w0rd` because PowerShell expands `$$`, and a value
      # containing a double quote ends the string early, which breaks the
      # generated script outright.
      #
      # @api private
      # @param value [Object] the value to escape; stringified first
      # @return [String] +value+ with `` ` ``, `$` and `"` backtick-escaped
      def escape_powershell_string(value)
        value.to_s.gsub(PS_DOUBLE_QUOTE_SPECIAL_CHARS) { |char| "`#{char}" }
      end

      # Renders a Ruby object as a PowerShell literal.
      #
      # Hashes become hashtables and arrays become arrays; every other value is
      # rendered as a double-quoted string, so Ruby booleans and integers reach
      # DSC quoted. Scalars are escaped by {#escape_powershell_string} so they
      # survive the round trip unchanged.
      #
      # @api private
      # @param obj [Hash, Array, Object] the value to render
      # @param depth [Integer] current indentation depth
      # @return [String] a PowerShell literal
      #
      # @example
      #   ps_hash("AllNodes" => [{ "NodeName" => "*" }])
      #   #=> %{@{\n  "AllNodes" =   @(\n@{\n        "NodeName" = "*"\n      }\n)\n}}
      def ps_hash(obj, depth = 0)
        if obj.is_a?(Hash)
          obj.map do |k, v|
            %{#{pad(depth + 2)}#{ps_hash(k)} = #{ps_hash(v, depth + 2)}}
          end.join(";\n").insert(0, "@{\n").insert(-1, "\n#{pad(depth)}}")
        elsif obj.is_a?(Array)
          array_string = obj.map { |v| ps_hash(v, depth + 4) }.join(",")
          "#{pad(depth)}@(\n#{array_string}\n)"
        else
          %{"#{escape_powershell_string(obj)}"}
        end
      end

      # Copies the DSC configuration script into the sandbox.
      #
      # @api private
      # @return [void]
      # @raise [Errno::ENOENT] if the configured script does not exist
      def prepare_configuration_script
        configuration_script_file = File.join(config[:configuration_script_folder], config[:configuration_script])
        configuration_script_path = File.join(config[:kitchen_root], configuration_script_file)
        sandbox_configuration_script_path = File.join(sandbox_path, sandboxed_configuration_script)
        FileUtils.mkdir_p(File.dirname(sandbox_configuration_script_path))
        debug("Moving #{configuration_script_path} to #{sandbox_configuration_script_path}")
        FileUtils.cp(configuration_script_path, sandbox_configuration_script_path)
      end

      # Wraps a scalar in an array so `:configuration_name` may be given either
      # as a single name or as a list.
      #
      # @api private
      # @param thing [Object, Array] the value to normalize
      # @return [Array] +thing+ if it is already an array, otherwise `[thing]`
      def ensure_array(thing)
        if thing.is_a?(Array)
          thing
        else
          [thing]
        end
      end
    end
  end
end
