# -*- encoding: utf-8 -*-
#
# Author:: Steven Murawski (<steven.murawski@gmail.com>)
#
# Copyright (C) 2014 Steven Murawski
#
# Licensed under the Apache 2 License.
# See LICENSE for more details

require "fileutils"
require "pathname"
require "kitchen/provisioner/base"
require "kitchen/util"
require "dsc_lcm_configuration"

module Kitchen
  module Provisioner
    class Dsc < Base
      kitchen_provisioner_api_version 2

      attr_accessor :tmp_dir

      default_config :modules_path, "modules"

      default_config :configuration_script_folder, "examples"
      default_config :configuration_script, "dsc_configuration.ps1"
      default_config :configuration_name do |provisioner|
        provisioner.instance.suite.name
      end

      default_config :configuration_data_variable, "ConfigurationData"
      default_config :configuration_data

      default_config :nuget_force_bootstrap, true
      default_config :gallery_uri
      default_config :gallery_name
      default_config :modules_from_gallery

      default_config :dsc_local_configuration_manager_version, "wmf4"
      default_config :dsc_local_configuration_manager, {}

      def finalize_config!(instance)
        config[:dsc_local_configuration_manager] = lcm.lcm_config
        super(instance)
      end

      def install_command
        full_lcm_configuration_script = <<-EOH
        #{lcm.lcm_configuration_script}

        $null = SetupLCM
        Set-DscLocalConfigurationManager -Path ./SetupLCM | out-null
        EOH

        wrap_powershell_code(full_lcm_configuration_script)
      end

      def init_command
        script = <<-EOH
#{setup_config_directory_script}
#{install_module_script if install_modules?}
        EOH
        wrap_powershell_code(script)
      end

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

      def prepare_command
        info("Moving DSC Resources onto PSModulePath")
        info("Generating the MOF script for the configuration #{config[:configuration_name]}")
        stage_resources_and_generate_mof_script = <<-EOH
          Remove-Item -Recurse -Force c:/configurations
          if (Test-Path (join-path #{config[:root_path]} 'modules'))
          {
            dir ( join-path #{config[:root_path]} 'modules/*') -directory |
              copy-item -destination $env:programfiles/windowspowershell/modules/ -recurse -force
          }
          if (-not (test-path 'c:/configurations'))
          {
            mkdir 'c:/configurations' | out-null
          }
          $ConfigurationScriptPath = Join-path #{config[:root_path]} #{sandboxed_configuration_script}
          if (-not (test-path $ConfigurationScriptPath))
          {
            throw "Failed to find $ConfigurationScriptPath"
          }
          invoke-expression (get-content $ConfigurationScriptPath -raw) -ErrorVariable errors
          $errors
          if (-not (get-command #{config[:configuration_name]}))
          {
            throw "Failed to create a configuration command #{config[:configuration_name]}"
          }

          #{configuration_data_assignment unless config[:configuration_data].nil?}

          $null = #{config[:configuration_name]} -outputpath c:/configurations #{"-configurationdata $" + configuration_data_variable}
        EOH
        debug("Shelling out: #{stage_resources_and_generate_mof_script}")
        wrap_powershell_code(stage_resources_and_generate_mof_script)
      end

      def run_command
        config[:retry_on_exit_code] = [35] if config[:retry_on_exit_code].empty?
        config[:max_retries] = 3 if config[:max_retries] == 1

        info("Running the configuration #{config[:configuration_name]}")
        run_configuration_script = <<-EOH
          $job = start-dscconfiguration -Path c:/configurations/ -force
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

        debug("Shelling out: #{run_configuration_script}")
        wrap_powershell_code(run_configuration_script)
      end

      private

      def lcm
        @lcm ||= begin
          lcm_version = config[:dsc_local_configuration_manager_version]
          lcm_config = config[:dsc_local_configuration_manager]
          DscLcmConfiguration::Factory.create(lcm_version, lcm_config)
        end
      end

      def setup_config_directory_script
        "mkdir (split-path (join-path #{config[:root_path]} #{sandboxed_configuration_script})) -force | out-null"
      end

      def powershell_module_params(module_specification_hash)
        keys = module_specification_hash.keys.reject { |k| k.to_s.casecmp('force') == 0 }
        unless keys.any? { |k| k.to_s.downcase == 'repository' }
          keys.push(:repository)
          module_specification_hash[:repository] = psmodule_repository_name
        end
        keys.map { |key| "-#{key} #{module_specification_hash[key]}" }.join(' ')
      end

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

      def nuget_force_bootstrap
        return unless config[:nuget_force_bootstrap]
        info("Bootstrapping the nuget package provider for PowerShell PackageManagement.")
        "install-packageprovider nuget -force -forcebootstrap | out-null"
      end

      def psmodule_repository_name
        return "PSGallery" if config[:gallery_name].nil? && config[:gallery_uri].nil?
        return "testing"   if config[:gallery_name].nil?
        config[:gallery_name]
      end

      def register_psmodule_repository
        return if config[:gallery_uri].nil?
        info("Registering a new PowerShellGet Repository - #{psmodule_repository_name}")
        "register-packagesource -providername PowerShellGet -name '#{psmodule_repository_name}' -location '#{config[:gallery_uri]}' -force -trusted"
      end

      def install_module_script
        return if config[:modules_from_gallery].nil?
        <<-EOH
  #{nuget_force_bootstrap}
  #{register_psmodule_repository}
  #{powershell_modules.join("\n")}
        EOH
      end

      def install_modules?
        config[:dsc_local_configuration_manager_version] == "wmf5" &&
          !config[:modules_from_gallery].nil?
      end

      def configuration_data_variable
        config[:configuration_data_variable].nil? ? "ConfigurationData" : config[:configuration_data_variable]
      end

      def configuration_data_assignment
        "$" + configuration_data_variable + " = " + ps_hash(config[:configuration_data])
      end

      def wrap_powershell_code(code)
        wrap_shell_code(["$ProgressPreference = 'SilentlyContinue';", code].join("\n"))
      end

      def powershell_module?
        module_metadata_file = File.join(config[:kitchen_root], "#{module_name}.psd1")
        File.exist?(module_metadata_file)
      end

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

      def module_name
        File.basename(config[:kitchen_root])
      end

      def prepare_resource_style_directory
        sandbox_base_module_path = File.join(sandbox_path, "modules/#{module_name}")

        base = config[:kitchen_root]
        list_files(base).each do |src|
          dest = File.join(sandbox_base_module_path, src.sub("#{base}/", ""))
          FileUtils.mkdir_p(File.dirname(dest))
          debug("Staging #{src} ")
          debug("  at #{dest}")
          FileUtils.cp(src, dest, :preserve => true)
        end
      end

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

      def sandboxed_configuration_script
        File.join("configuration", config[:configuration_script])
      end

      def pad(depth = 0)
        " " * depth
      end

      def ps_hash(obj, depth = 0)
        if obj.is_a?(Hash)
          obj.map do |k, v|
            %{#{pad(depth + 2)}#{ps_hash(k)} = #{ps_hash(v, depth + 2)}}
          end.join(";\n").insert(0, "@{\n").insert(-1, "\n#{pad(depth)}}")
        elsif obj.is_a?(Array)
          array_string = obj.map { |v| ps_hash(v, depth + 4) }.join(",")
          "#{pad(depth)}@(\n#{array_string}\n)"
        else
          %{"#{obj}"}
        end
      end

      def prepare_configuration_script
        configuration_script_file = File.join(config[:configuration_script_folder], config[:configuration_script])
        configuration_script_path = File.join(config[:kitchen_root], configuration_script_file)
        sandbox_configuration_script_path = File.join(sandbox_path, sandboxed_configuration_script)
        FileUtils.mkdir_p(File.dirname(sandbox_configuration_script_path))
        debug("Moving #{configuration_script_path} to #{sandbox_configuration_script_path}")
        FileUtils.cp(configuration_script_path, sandbox_configuration_script_path)
      end
    end
  end
end
