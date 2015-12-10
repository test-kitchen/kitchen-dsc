[![Gem Version](https://badge.fury.io/rb/kitchen-dsc.svg)](http://badge.fury.io/rb/kitchen-dsc)

# kitchen-dsc
A Test Kitchen Provisioner for PowerShell DSC


## Requirements
You'll need a driver box with WMF4 or greater (ONLY WINDOWS SYSTEMS)

## Installation & Setup
You'll need the test-kitchen & kitchen-dsc gems installed in your system, along with kitchen-vagrant or some ther suitable driver for test-kitchen. 

## Example Configurations
* [Repository Style Testing](https://github.com/smurawski/dsc-kitchen-project)
* [Module Style Testing](https://github.com/powershellorg/cwebadministration/tree/smurawski/adding_tests)

## Configuration Settings
* configuration_script_folder
  * Defaults to 'examples'.
  * The location of a PowerShell script(s) containing the DSC configuration command(s).
* configuration_script
  * Defaults to 'dsc_configuration.ps1'
  * The name of the PowerShell script containing the DSC configuration command(s) (and possibly configuration data)
* configuration_name
  * Name of the configuration to run, defaults to the suite name.
* configuration_data_variable
  * Name of the variable in the configuration_script that contains the ConfigurationData hashtable
* dsc_local_configuration_manager_version
  * Defaults to 'wmf4' ()
  * Identifies what version of the LCM is in place
  * Other valid values are 'wmf4_with_update' and 'wmf5'
    * Currently the only difference between wmf4 and wmf4_with_update/wmf5 is the action_after_reboot and the debug_mode settings.  Eventually, I'd like to add support for partial configurations, pull servers, etc..
  * In this context, wmf4_with_update refers to wmf4 with KB3000850 applied (to add support for WMF 5 generated configurations, plus some fixes).
* dsc_local_configuration_manager
  * Settings for the LCM
  * Defaults are:
    * action_after_reboot = 'StopConfiguration' # wmf4_with_update or wmf5
    * allow_module_overwrite = false
    * certificate_id = nil
    * configuration_mode = 'ApplyAndAutoCorrect'
    * configuration_mode_frequency_mins = 30    # 15 on wmf5
    * debug_mode = 'All'                        # wmf4_with_update
    * refresh_frequency_mins = 15               # 30 on wmf5
    * refresh_mode = 'PUSH'

### Specific to repository style testing
* modules_path
  * Defaults to 'modules'.
  * Points to the location of modules containing DSC resources to upload
  * This path is relative to the root of the repository (the location of the .kitchen.yml).
