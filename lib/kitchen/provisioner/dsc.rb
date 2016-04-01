# -*- encoding: utf-8 -*-
#
# Author:: Steven Murawski (<steven.murawski@gmail.com>)
#
# Copyright (C) 2014 Steven Murawski
#
# Licensed under the MIT License.
# See LICENSE for more details

require 'fileutils'
require 'pathname'
require 'kitchen/provisioner/base'
require 'kitchen/util'

module Kitchen
  module Provisioner
    class Dsc < Base
      kitchen_provisioner_api_version 2

      attr_accessor :tmp_dir

      default_config :modules_path, 'modules'

      default_config :configuration_script_folder, 'examples'
      default_config :configuration_script, 'dsc_configuration.ps1'
      default_config :configuration_name do |provisioner|
        provisioner.instance.suite.name
      end

      default_config :configuration_data_variable, 'ConfigurationData'
      default_config :configuration_data

      default_config :nuget_force_bootstrap, true
      default_config :gallery_uri
      default_config :gallery_name
      default_config :modules_from_gallery

      default_config :dsc_local_configuration_manager_version, 'wmf4'
      default_config :dsc_local_configuration_manager

      def override_lcm_setting?(name)
        if config[:dsc_local_configuration_manager].nil? ||
           config[:dsc_local_configuration_manager][name.to_sym].nil?
          false
        else
          true
        end
      end

      def resolve_lcm_setting(name, default_value)
        if override_lcm_setting? name
          config[:dsc_local_configuration_manager][name.to_sym]
        else
          default_value
        end
      end

      def lcm_settings
        {
          action_after_reboot: (resolve_lcm_setting 'action_after_reboot', 'StopConfiguration'),
          allow_module_overwrite: (resolve_lcm_setting 'allow_module_overwrite', false),
          certificate_id: (resolve_lcm_setting 'certificate_id', nil),
          configuration_mode: (resolve_lcm_setting 'configuration_mode', 'ApplyAndAutoCorrect'),
          debug_mode: (resolve_lcm_setting 'debug_mode', 'All'),
          reboot_if_needed: (resolve_lcm_setting 'reboot_if_needed', false),
          refresh_mode: (resolve_lcm_setting 'refresh_mode', 'PUSH')
        }
      end

      def install_command
        lcm_config = lcm_settings
        case config[:dsc_local_configuration_manager_version]
        when 'wmf4_legacy', 'wmf4'
          lcm_configuration_script = <<-LCMSETUP
            configuration SetupLCM
            {
              LocalConfigurationManager
              {
                AllowModuleOverwrite = [bool]::Parse('#{lcm_config[:allow_module_overwrite]}')
                CertificateID = '#{lcm_config[:certificate_id].nil? ? '$null' : lcm_config[:certificate_id]}'
                ConfigurationMode = '#{lcm_config[:configuration_mode]}'
                ConfigurationModeFrequencyMins = #{lcm_config[:configuration_mode_frequency_mins].nil? ? '30' : lcm_config[:configuration_mode_frequency_mins]}
                RebootNodeIfNeeded = [bool]::Parse('#{lcm_config[:reboot_if_needed]}')
                RefreshFrequencyMins = #{lcm_config[:refresh_frequency_mins].nil? ? '15' : lcm_config[:refresh_frequency_mins]}
                RefreshMode = '#{lcm_config[:refresh_mode]}'
              }
            }
          LCMSETUP
        when 'wmf4_with_update'
          lcm_configuration_script = <<-LCMSETUP
            configuration SetupLCM
            {
              LocalConfigurationManager
              {
                ActionAfterReboot = '#{lcm_config[:action_after_reboot]}'
                AllowModuleOverwrite = [bool]::Parse('#{lcm_config[:allow_module_overwrite]}')
                CertificateID = '#{lcm_config[:certificate_id].nil? ? '$null' : lcm_config[:certificate_id]}'
                ConfigurationMode = '#{lcm_config[:configuration_mode]}'
                ConfigurationModeFrequencyMins = #{lcm_config[:configuration_mode_frequency_mins].nil? ? '30' : lcm_config[:configuration_mode_frequency_mins]}
                DebugMode = '#{lcm_config[:debug_mode]}'
                RebootNodeIfNeeded = [bool]::Parse('#{lcm_config[:reboot_if_needed]}')
                RefreshFrequencyMins = #{lcm_config[:refresh_frequency_mins].nil? ? '15' : lcm_config[:refresh_frequency_mins]}
                RefreshMode = '#{lcm_config[:refresh_mode]}'
              }
            }
          LCMSETUP
        when 'wmf5'
          lcm_configuration_script = <<-LCMSETUP
            [DSCLocalConfigurationManager()]
            configuration SetupLCM
            {
              Settings
              {
                ActionAfterReboot = '#{lcm_config[:action_after_reboot]}'
                AllowModuleOverwrite = [bool]::Parse('#{lcm_config[:allow_module_overwrite]}')
                CertificateID = '#{lcm_config[:certificate_id].nil? ? '$null' : lcm_config[:certificate_id]}'
                ConfigurationMode = '#{lcm_config[:configuration_mode]}'
                ConfigurationModeFrequencyMins = #{lcm_config[:configuration_mode_frequency_mins].nil? ? '15' : lcm_config[:configuration_mode_frequency_mins]}
                DebugMode = '#{lcm_config[:debug_mode]}'
                RebootNodeIfNeeded = [bool]::Parse('#{lcm_config[:reboot_if_needed]}')
                RefreshFrequencyMins = #{lcm_config[:refresh_frequency_mins].nil? ? '30' : lcm_config[:refresh_frequency_mins]}
                RefreshMode = '#{lcm_config[:refresh_mode]}'
              }
            }
          LCMSETUP
        end
        full_lcm_configuration_script = <<-EOH
        #{lcm_configuration_script}

        $null = SetupLCM
        Set-DscLocalConfigurationManager -Path ./SetupLCM | out-null
        EOH

        wrap_shell_code(full_lcm_configuration_script)
      end
      # rubocop:enable Metrics/LineLength

      def setup_config_directory_script
        "mkdir (split-path (join-path #{config[:root_path]} #{sandboxed_configuration_script})) -force | out-null"
      end

      def powershell_modules
        Array(config[:modules_from_gallery]).map do |powershell_module|
          params = if powershell_module.is_a? Hash
                     keys = powershell_module.keys.reject { |k| k.to_s.downcase! == 'force' }
                     unless keys.any? { |k| k.to_s.downcase! == 'repository' }
                       keys.push(:repository)
                       powershell_module[:repository] = psmodule_repository_name
                     end
                     keys.map do |key|
                       "-#{key} #{powershell_module[key]}"
                     end.join(' ')
                   else
                     "-name '#{powershell_module}' -Repository -Repository #{psmodule_repository_name}"
                   end
          "install-module #{params} -force | out-null"
        end
      end

      def nuget_force_bootstrap
        return unless config[:nuget_force_bootstrap]
        info('Bootstrapping the nuget package provider for PowerShell PackageManagement.')
        'install-packageprovider nuget -force -forcebootstrap | out-null'
      end

      def psmodule_repository_name
        return 'PSGallery' if config[:gallery_name].nil? && config[:gallery_uri].nil?
        return 'testing'   if config[:gallery_name].nil?
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
        config[:dsc_local_configuration_manager_version] == 'wmf5' &&
          !config[:modules_from_gallery].nil?
      end

      def init_command
        script = <<-EOH
#{setup_config_directory_script}
#{install_module_script if install_modules?}
        EOH
        wrap_shell_code(script)
      end

      def create_sandbox
        super
        info('Staging DSC Resource Modules for copy to the SUT')
        if resource_module? || class_resource_module?
          prepare_resource_style_directory
        else
          prepare_repo_style_directory
        end
        info('Staging DSC configuration script for copy to the SUT')
        prepare_configuration_script
      end

      def prepare_command
        info('Moving DSC Resources onto PSModulePath')
        info("Generating the MOF script for the configuration #{config[:configuration_name]}")
        stage_resources_and_generate_mof_script = <<-EOH
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
          invoke-expression (get-content $ConfigurationScriptPath -raw)
          if (-not (get-command #{config[:configuration_name]}))
          {
            throw "Failed to create a configuration command #{config[:configuration_name]}"
          }

          #{configuration_data_assignment unless config[:configuration_data].nil?}

          $null = #{config[:configuration_name]} -outputpath c:/configurations #{'-configurationdata $' + configuration_data_variable}
        EOH
        debug("Shelling out: #{stage_resources_and_generate_mof_script}")
        wrap_shell_code(stage_resources_and_generate_mof_script)
      end
      # rubocop:enable Metrics/LineLength

      def configuration_data_variable
        config[:configuration_data_variable].nil? ? 'ConfigurationData' : config[:configuration_data_variable]
      end

      def configuration_data_assignment
        '$' + configuration_data_variable + ' = ' + ps_hash(config[:configuration_data])
      end

      def run_command
        info("Running the configuration #{config[:configuration_name]}")
        run_configuration_script = <<-EOH
          $ProgressPreference = 'SilentlyContinue'
          $job = start-dscconfiguration -Path c:/configurations/ -force
          $job | wait-job
          $job.childjobs[0].verbose
          $dsc_errors = $job.childjobs[0].Error
          if ($dsc_errors -ne $null) {
            $dsc_errors
            exit 1
          }
        EOH

        debug("Shelling out: #{run_configuration_script}")
        wrap_shell_code(run_configuration_script)
      end

      private

      def resource_module?
        module_metadata_file = File.join(config[:kitchen_root], "#{module_name}.psd1")
        module_dsc_resource_folder = File.join(config[:kitchen_root], 'DSCResources')
        File.exist?(module_metadata_file) &&
          File.exist?(module_dsc_resource_folder)
      end

      def class_resource_module?
        module_metadata_file = File.join(config[:kitchen_root], "#{module_name}.psd1")
        module_dsc_resource_folder = File.join(config[:kitchen_root], 'DSCResources')
        File.exist?(module_metadata_file) &&
          !File.exist?(module_dsc_resource_folder)
      end

      def list_files(path)
        base_directory_content = Dir.glob(File.join(path, '*'))
        nested_directory_content = Dir.glob(File.join(path, '*/**/*'))
        all_directory_content = [base_directory_content, nested_directory_content].flatten

        ignore_files = ['Gemfile', 'Gemfile.lock', 'README.md', 'LICENSE.txt']
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
          dest = File.join(sandbox_base_module_path, src.sub("#{base}/", ''))
          FileUtils.mkdir_p(File.dirname(dest))
          debug("Staging #{src} ")
          debug("  at #{dest}")
          FileUtils.cp(src, dest, preserve: true)
        end
      end

      def prepare_repo_style_directory
        module_path = File.join(config[:kitchen_root], config[:modules_path])
        sandbox_module_path = File.join(sandbox_path, 'modules')

        if Dir.exist?(module_path)
          debug("Moving #{module_path} to #{sandbox_module_path}")
          FileUtils.cp_r(module_path, sandbox_module_path)
        else
          debug("The modules path #{module_path} was not found. Not moving to #{sandbox_module_path}.")
        end
      end

      def sandboxed_configuration_script
        File.join('configuration', config[:configuration_script])
      end

      def pad(depth = 0)
        ' ' * depth
      end

      def ps_hash(obj, depth = 0)
        if obj.is_a?(Hash)
          obj.map do |k, v|
            %(#{pad(depth + 2)}#{ps_hash(k)} = #{ps_hash(v, depth + 2)})
          end.join(";\n").insert(0, "@{\n").insert(-1, "\n#{pad(depth)}}")
        elsif obj.is_a?(Array)
          array_string = obj.map { |v| ps_hash(v, depth + 4) }.join(',')
          "#{pad(depth)}@(\n#{array_string}\n)"
        else
          %("#{obj}")
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
