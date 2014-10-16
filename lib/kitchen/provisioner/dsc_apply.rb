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
require 'json'
require 'kitchen/provisioner/base'
require 'kitchen/util'

module Kitchen
  class Busser
    def non_suite_dirs
      %w(data data_bags environments nodes roles)
    end
  end

  module Provisioner
    #
    #
    #
    class DscApply < Base
      attr_accessor :tmp_dir

      default_config :modules_path, 'modules'
      default_config :configuration_script, 'dsc_configuration.ps1'

      def install_command
        nil
      end

      def init_command
      end

      def create_sandbox
        super
        FileUtils.mkdir_p(sandbox_path)

        # Stage DSC Resource Modules for copy to SUT
        FileUtils.cp_r(File.join(config[:kitchen_root], config[:modules_path]), File.join(sandbox_path, 'modules'))
        FileUtils.cp(File.join(config[:kitchen_root], config[:configuration_script]), File.join(sandbox_path, 'dsc_configuration.ps1'))
      end

      def prepare_command
        # Move DSC Resources onto PSModulePath
        stage_resources_script = <<-EOH
          dir 'c:/tmp/kitchen/modules/*' -directory | copy-item -destination $env:programfiles/windowspowershell/modules/ -recurse -force
        EOH
        Util.wrap_command(stage_resources_script, shell)

        # Generate the MOF script
        generate_mof_script = <<-EOH
          . c:/tmp/kitchen/dsc_configuration.ps1
          test -outputpath c:/tmp/kitchen/configurations
        EOH

        Util.wrap_command(generate_mof_script, shell)
      end

      def run_command
        # Run the configuration and return the results
        run_configuration_script = <<-EOH
          $job = start-dscconfiguration -Path c:/tmp/kitchen/configurations/
          $job | wait-job
          $job.childjobs[0].verbose
        EOH
        Util.wrap_command(run_configuration_script, shell)
      end
    end
  end
end
