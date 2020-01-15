#
# Author:: Steven Murawski (<steven.murawski@gmail.com>)
#
# Copyright (C) 2014 Steven Murawski
#
# Licensed under the Apache 2 License.
# See LICENSE for more details

require "kitchen/provisioner/dsc_lcm/lcm_base"

module Kitchen
  module Provisioner
    module DscLcm
      class LcmV5 < LcmBase

        def lcm_properties
          {
            action_after_reboot: "StopConfiguration",
            allow_module_overwrite: false,
            certificate_id: nil,
            configuration_mode: "ApplyAndAutoCorrect",
            configuration_mode_frequency_mins: 15,
            debug_mode: "All",
            reboot_if_needed: false,
            refresh_mode: "PUSH",
            refresh_frequency_mins: 30,
          }
        end

        def lcm_configuration_script
          <<-LCMSETUP
            [DSCLocalConfigurationManager()]
            configuration SetupLCM
            {
              Settings
              {
                ActionAfterReboot = '#{action_after_reboot}'
                AllowModuleOverwrite = [bool]::Parse('#{allow_module_overwrite}')
                CertificateID = #{certificate_id}
                ConfigurationMode = '#{configuration_mode}'
                ConfigurationModeFrequencyMins = #{configuration_mode_frequency_mins}
                DebugMode = '#{debug_mode}'
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
