# -*- encoding: utf-8 -*-
#
# Author:: Steven Murawski (<steven.murawski@gmail.com>)
#
# Copyright (C) 2014 Steven Murawski
#
# Licensed under the MIT License.  
# See LICENSE for more details

require 'json'
require 'kitchen/provisioner/base'


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
      
      default_config :resource_module_path do |provisioner|
        provisioner.calculate_path('Modules', :directory )
      end

      default_config :configuration_data_remote_path do |provisioner|
        provisioner.calculate_path('ConfigurationData')
      end      

      default_config :configuration_script do |provisioner|
        provisioner.calculate_path('configuration.ps1', :file) or
          raise 'No configuration_script detected. Please specify one in .kitchen.yml'
      end

      default_config :dsc_verbose, false      

      def calculate_path(path, type = :directory)
        base = config[:test_base_path]
        candidates = []
        candidates << File.join(base, instance.suite.name, 'dsc', path)
        candidates << File.join(base, instance.suite.name, path)
        candidates << File.join(base, path)
        candidates << File.join(Dir.pwd, path)

        candidates.find do |c|
          type == :directory ? File.directory?(c) : File.file?(c)
        end
      end      
    end
  end
end
