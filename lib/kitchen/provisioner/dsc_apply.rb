# -*- encoding: utf-8 -*-
#
# Author:: Steven Murawski (<steven.murawski@gmail.com>)
#
# Copyright (C) 2014 Steven Murawski
#
# Licensed under the MIT License.  
# See LICENSE for more details

require "fileutils"
require "pathname"
require 'json'
require 'kitchen/provisioner/base'
require "kitchen/util"


module Kitchen

  class Busser

    def non_suite_dirs
      %w{data data_bags environments nodes roles puppet}
    end
  end

  module Provisioner
    #
    # Puppet Apply provisioner.
    #
    class DscApply < Base
      attr_accessor :tmp_dir

      default_config :powershell_version, nil
      
      default_config :resource_module_path, 'Modules'

      default_config :configuration_data_remote_path, 'ConfigurationData'

      default_config :configuration_script, 'configuration.ps1'        

      default_config :dsc_verbose, false      

      def install_command
        return nil
      end

      def init_command 
        firstline = "if (test-path #{config[:root_path]}) {remove-item -recurse -force #{config[:root_path]}}"
        secondline = "mkdir #{config[:root_path]} | out-null"
        lines = [firstline, secondline]
        Util.wrap_command(lines.join("\n"), shell)
      end      

      def create_sandbox
        super
        FileUtils.mkdir_p(sandbox_path)
        FileUtils.cp_r(config[:root_path], sandbox_path)
        #Copy Modules and Configuration Data
        #Copy Configuration Script
      end

      def prepare_command
        generateconfig = "./configuration.ps1"
        Util.wrap_command(generateconfig, shell)
      end

      def run_command
        runconfig = "start-dscconfiguration -Wait -Verbose -Path ./TestKitchen"
        Util.wrap_command(runconfig, shell)
      end
      
    end
  end
end
