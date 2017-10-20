[![Gem Version](https://badge.fury.io/rb/kitchen-dsc.svg)](http://badge.fury.io/rb/kitchen-dsc)

# kitchen-dsc
A Test Kitchen Provisioner for PowerShell DSC


## Requirements
You'll need a driver box with WMF4 or greater (ONLY WINDOWS SYSTEMS)

## Installation & Setup
You'll need the test-kitchen & kitchen-dsc gems installed in your system, along with kitchen-vagrant or some ther suitable driver for test-kitchen. 

### Note:
You will see a delay in the return of the run details due to an difference in how the verbose stream is returned for DSC runs between WMF versions, so I return the verbose stream after the job completes.  I'd love to live stream the results, but that'll take a bit more experimentation. (PR's welcome!)

## Example Configurations
* [Repository Style Testing](https://github.com/smurawski/dsc-kitchen-project)
* [Module Style Testing](https://github.com/powershellorg/cwebadministration/tree/smurawski/adding_tests)

## Configuration Settings
* configuration_script_folder
  * Defaults to 'examples'.
  * The location of a PowerShell script(s) containing the DSC configuration command(s).
  * The whole content of the folder will be copied to the node

* configuration_script
  * Defaults to 'dsc_configuration.ps1'
  * The name of the PowerShell script containing the DSC configuration command(s) (and possibly configuration data)
  * can be a relative path from the configuration_script_folder
  * the configuration script is dot sourced
  * if the configuration_script is set to `MOF` it will not execute a configuration script but copy
  the content of configuration_script_folder as-is, so that MOF from those directories can be applied.

* configuration_name
  * Name of the configurations to run, defaults to the suite name.
  * This can be an array of configuration from the same configuration script.
  * When applying MOFs directly, the path expected is `configuration_script_folder\configuration_name\*.mof`

* configuration_data
  * A YAML representation of what should be passed to the configuration.
  * Overrides any configurationdata variable assigned in the configuration script.

* configuration_data_variable
  * Defaults to 'ConfigurationData'
  * Name of the variable that contains the ConfigurationData hashtable
  * Can be defined in the configuration script or via the `configuration_data` configuration setting.

* dsc_local_configuration_manager_version
  * Defaults to 'wmf4' 
  * Identifies what version of the LCM is in place
  * Other valid values are 'wmf4_with_update' and 'wmf5'
    * Currently the only difference between wmf4 and wmf4_with_update/wmf5 is the action_after_reboot and the debug_mode settings.  Eventually, I'd like to add support for partial configurations, pull servers, etc..
  * In this context, wmf4_with_update refers to wmf4 with KB3000850 applied (to add support for WMF 5 generated configurations, plus some fixes).

* dsc_local_configuration_manager
  * Settings for the LCM
  * Defaults are:
    * action_after_reboot = 'StopConfiguration' # wmf4_with_update or wmf5
    * reboot_if_needed = false
    * allow_module_overwrite = false
    * certificate_id = nil
    * configuration_mode = 'ApplyAndAutoCorrect'
    * configuration_mode_frequency_mins = 30    # 15 on wmf5
    * debug_mode = 'All'                        # wmf4_with_update
    * refresh_frequency_mins = 15               # 30 on wmf5
    * refresh_mode = 'PUSH'

* modules_from_gallery
  * Requires WMF 5
  * Takes a string (for one module) or an array (for multiple) to install from the gallery
  * Or takes a hash with keys matching the parameters for install-module.  
    * Name is required.  
    * Force is automatically used and not required as part of the hash table.
    * Repository defaults to either PSGallery or any custom feed defined, but can be overriden here.

* gallery_name
  * Custom PowerShell gallery name to install modules from.
  * If there is no package source with this name registered on the machine, then gallery_uri must be configured as well.

* gallery_uri
  * URI for a custom PowerShell gallery feed.

* modules_path
  * Defaults to 'modules'.
  * Points to the location of modules containing DSC resources to upload
  * This path is relative to the root of the repository (the location of the .kitchen.yml).
  * this works for both Repository and Resource style testing

## Example 

```yaml
provisioner:
  - name: dsc
    dsc_local_configuration_manager_version: wmf5
    dsc_local_configuration_manager:
      reboot_if_needed: true
      debug_mode: none
    configuration_script_folder: .
    configuration_script: SampleConfig.ps1
    gallery_uri: https://ci.appveyor.com/nuget/xWebAdministration
    gallery_name: xWebDevFeed
    modules_from_gallery:
      - xWebAdministration
      - name: xComputerManagement
        requiredversion: 1.4.0.0
        repository: PSGallery

suite:
  - name: test
    provisioner:
      configuration_data:
        AllNodes:
          - nodename: localhost
            role: webserver
```

Now you can also:
  - apply MOF(s) directly
  - copy the whole content of the `configuration_script_folder`, 
  allowing more complex configs
  - Copy modules from module_path to the node in Resource Repo
  - store your kitchen.yml file in the parent folder of a Module where
  the structure follows this:
  ```
  MODULENAME
  │   .kitchen.yml
  │
  ├───ModuleName
  │   │   ModuleName.psd1
  │   │
  │   └───DscResources
  └───Modules
      └───xNetworking
    ```
  