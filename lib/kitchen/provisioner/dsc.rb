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
      default_config :configuration_data_variable

      default_config :dsc_local_configuration_manager_version, 'wmf4'
      default_config :dsc_local_configuration_manager, {
        action_after_reboot: 'StopConfiguration',
        allow_module_overwrite: false,
        certificate_id: nil,
        configuration_mode: 'ApplyAndAutoCorrect',
        configuration_mode_frequency_mins: 30,
        debug_mode: 'All',
        reboot_if_needed: false,
        refresh_frequency_mins: 15,
        refresh_mode: 'PUSH'
      }

      # Disable line length check, it is all embedded script.
      # rubocop:disable Metrics/LineLength
      def install_command
        lcm_config = config[:dsc_local_configuration_manager]
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
                ConfigurationModeFrequencyMins = #{lcm_config[:configuration_mode_frequency_mins]}
                RebootNodeIfNeeded = [bool]::Parse('#{lcm_config[:reboot_if_needed]}')
                RefreshFrequencyMins = #{lcm_config[:refresh_frequency_mins]}
                RefreshMode = '#{lcm_config[:refresh_mode]}'
              }
            }
            SetupLCM
            Set-DscLocalConfigurationManager -Path ./SetupLCM
          LCMSETUP
        when 'wmf4_with_update', 'wmf5'
          lcm_configuration_script = <<-LCMSETUP
            configuration SetupLCM
            {
              LocalConfigurationManager
              {
                ActionAfterReboot = '#{lcm_config[:action_after_reboot]}'
                AllowModuleOverwrite = [bool]::Parse('#{lcm_config[:allow_module_overwrite]}')
                CertificateID = '#{lcm_config[:certificate_id].nil? ? '$null' : lcm_config[:certificate_id]}'
                ConfigurationMode = '#{lcm_config[:configuration_mode]}'
                ConfigurationModeFrequencyMins = #{lcm_config[:configuration_mode_frequency_mins]}
                DebugMode = '#{lcm_config[:debug_mode]}'
                RebootNodeIfNeeded = [bool]::Parse('#{lcm_config[:reboot_if_needed]}')
                RefreshFrequencyMins = #{lcm_config[:refresh_frequency_mins]}
                RefreshMode = '#{lcm_config[:refresh_mode]}'
              }
            }
            $null = SetupLCM
            Set-DscLocalConfigurationManager -Path ./SetupLCM
          LCMSETUP
        end
        wrap_shell_code(lcm_configuration_script)
      end
      # rubocop:enable Metrics/LineLength

      def init_command
      end

      def create_sandbox
        super
        info('Staging DSC Resource Modules for copy to the SUT')
        if resource_module?
          prepare_resource_style_directory
        else
          prepare_repo_style_directory
        end
        info('Staging DSC configuration script for copy to the SUT')
        prepare_configuration_script
      end

      # Disable line length check, it is all logging and embedded script.
      # rubocop:disable Metrics/LineLength
      def prepare_command
        info('Moving DSC Resources onto PSModulePath')
        info("Generating the MOF script for the configuration #{config[:configuration_name]}")
        stage_resources_and_generate_mof_script = <<-EOH
          dir ( join-path #{config[:root_path]} 'modules/*') -directory |
            copy-item -destination $env:programfiles/windowspowershell/modules/ -recurse -force

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
          $null = #{config[:configuration_name]} -outputpath c:/configurations #{'-configurationdata $' + config[:configuration_data_variable] if config[:configuration_data_variable]}
        EOH
        debug("Shelling out: #{stage_resources_and_generate_mof_script}")
        wrap_shell_code(stage_resources_and_generate_mof_script)
      end
      # rubocop:enable Metrics/LineLength

      def run_command
        info("Running the configuration #{config[:configuration_name]}")
        run_configuration_script = <<-EOH
          $job = start-dscconfiguration -Path c:/configurations/ -force
          $job | wait-job
          $job.childjobs[0].verbose
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

      def list_files(path)
        base_directory_content = Dir.glob(File.join(path, '*'))
        nested_directory_content = Dir.glob(File.join(path, '*/**/*'))
        all_directory_content =([base_directory_content, nested_directory_content]).flatten

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

        debug("Moving #{module_path} to #{sandbox_module_path}")
        FileUtils.cp_r(module_path, sandbox_module_path)
      end

      def sandboxed_configuration_script
        File.join('configuration', config[:configuration_script])
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
