# -*- encoding: utf-8 -*-
#
# Author:: Steven Murawski (<steven.murawski@gmail.com>)
#
# Copyright (C) 2014 Steven Murawski
#
# Licensed under the Apache 2 License.
# See LICENSE for more details

require "kitchen/provisioner/dsc_lcm/lcm_v4"
require "kitchen/provisioner/dsc_lcm/lcm_v5"

module Kitchen
  module Provisioner
    module DscLcm
      class LcmBase

        

        def lcm_properties
          {
            :allow_module_overwrite => false,
            :certificate_id => nil,
            :configuration_mode => "ApplyAndAutoCorrect",
            :configuration_mode_frequency_mins => 30,
            :reboot_if_needed => false,
            :refresh_mode => "PUSH",
            :refresh_frequency_mins => 15
          }
        end

        def initialize(config = {})
          @certificate_id = nil
          lcm_properties.each do |setting, value|
            send(setting, value)
          end

          config.each do |setting, value|
            send(setting, value)
          end
        end

        def method_missing(name, *args)
          return super unless lcm_properties.keys.include?(name)
          if args.length == 1
            instance_variable_set("@#{name}", args.first)
          else
            instance_variable_get("@#{name}")
          end
        end

        def certificate_id(value = nil)
          if value.nil?
            @certificate_id.nil? ? "$null" : "'#{@certificate_id}'"
          else
            @certificate_id = value
          end
        end

        def lcm_config
          hash = {}
          lcm_properties.keys.each do |key|
            hash[key] = send(key)
          end
          hash
        end

        def lcm_configuration_script
          <<-LCMSETUP
            configuration SetupLCM
            {
              LocalConfigurationManager
              {
                AllowModuleOverwrite = [bool]::Parse('#{allow_module_overwrite}')
                CertificateID = #{certificate_id}
                ConfigurationMode = '#{configuration_mode}'
                ConfigurationModeFrequencyMins = #{configuration_mode_frequency_mins}
                RebootNodeIfNeeded = [bool]::Parse('#{reboot_if_needed}')
                RefreshFrequencyMins = #{refresh_frequency_mins}
                RefreshMode = '#{refresh_mode}'
              }
            }
          LCMSETUP
        end
      end
    end
  end
end
