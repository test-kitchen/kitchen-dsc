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
      default_config :configuration_script, 'dsc_configuration.ps1'


      default_config :dsc_local_configuration_manager, {
        :wmf4 => {
          :reboot_if_needed => false
        },
        :wmf5 => {
          :reboot_if_needed => false,
          :debug_mode => false
        }
      }

      def install_command
      end

      def init_command
      end

      def create_sandbox
        super
        FileUtils.mkdir_p(sandbox_path)

        info('Staging DSC Resource Modules for copy to the SUT')
        FileUtils.cp_r(File.join(config[:kitchen_root], config[:modules_path]), File.join(sandbox_path, 'modules'))
        FileUtils.cp(File.join(config[:kitchen_root], config[:configuration_script]), File.join(sandbox_path, 'dsc_configuration.ps1'))
      end

      def prepare_command
        info('Moving DSC Resources onto PSModulePath')
        info("Generating the MOF script for the configuration #{current_configuration}")

        stage_resources_and_generate_mof_script = <<-EOH

          dir ( join-path #{config[:root_path]} 'modules/*') -directory |
            copy-item -destination $env:programfiles/windowspowershell/modules/ -recurse -force

          mkdir 'c:/configurations' | out-null
          . #{remote_path_join( config[:root_path], config[:configuration_script])}
          #{current_configuration} -outputpath c:/configurations | out-null

        EOH

        wrap_shell_code(stage_resources_and_generate_mof_script)
      end

      def run_command
        info("Running the configuration #{current_configuration}")
        run_configuration_script = <<-EOH

          $job = start-dscconfiguration -Path c:/configurations/
          $job | wait-job
          $job.childjobs[0].verbose

        EOH
        wrap_shell_code(run_configuration_script)
      end

      private

      def current_configuration
        config.keys.include?(:run_list) ? config[:run_list][0] : @instance.suite.name
      end

      def is_resource_module?
        #TODO
      end

    end
  end
end
