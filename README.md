# kitchen-dsc

[![Gem Version](https://badge.fury.io/rb/kitchen-dsc.svg)](http://badge.fury.io/rb/kitchen-dsc)

A [Test Kitchen](https://kitchen.ci/) provisioner that applies [PowerShell Desired State Configuration](https://learn.microsoft.com/en-us/powershell/dsc/overview) configurations to test instances, so you can test DSC configurations and resources the same way you would test a cookbook.

> **This project is no longer under active development.** It has no active
> maintainers. The provisioner may continue to work for some or all use cases,
> but issues filed on GitHub will most likely not be triaged. If you are
> interested in maintaining it, come and talk to us in `#test-kitchen` on
> [Chef Community Slack](https://community-slack.chef.io/).

<!-- -->

> This documentation uses [Cinc Workstation](https://cinc.sh/) and the `cinc` commands throughout. Everything here works identically with Chef Workstation — see [Using with Chef](#using-with-chef).

## Contents

* [Requirements](#requirements)
* [Installation](#installation)
* [Two ways to lay out a project](#two-ways-to-lay-out-a-project)
* [Quick Start](#quick-start)
* [How it works](#how-it-works)
* [Configuration](#configuration)
* [Examples](#examples)
* [Using with Chef](#using-with-chef)
* [Troubleshooting](#troubleshooting)
* [Contributing](#contributing)
* [License](#license)

## Requirements

- **Windows test instances only.** The instance must be running WMF 4 or newer.
- A Test Kitchen driver that can provide Windows instances, such as
  [kitchen-vagrant](https://github.com/test-kitchen/kitchen-vagrant),
  [kitchen-hyperv](https://github.com/test-kitchen/kitchen-hyperv), or
  [kitchen-ec2](https://github.com/test-kitchen/kitchen-ec2)
- WMF 5 if you want to install modules from a PowerShell gallery

## Installation

Add the provisioner to your `Gemfile` alongside Test Kitchen and a driver:

```ruby
gem "test-kitchen"
gem "kitchen-dsc"
gem "kitchen-vagrant"
```

Then:

```sh
bundle install
```

Or install it directly:

```sh
gem install kitchen-dsc
```

## Two ways to lay out a project

How you configure this provisioner depends on what you are testing.

**Module style** keeps the DSC configuration next to the module it exercises.
Point `configuration_script_folder` and `configuration_script` at that file.

**Repository style** keeps a `modules` directory of DSC resources at the root of
the repository, which the provisioner uploads to the instance before applying
the configuration. `modules_path` controls where that directory is.

Worked examples of each:

- [Repository style testing](https://github.com/smurawski/dsc-kitchen-project)
- [Module style testing](https://github.com/powershellorg/cwebadministration/tree/smurawski/adding_tests)

## Quick Start

Put a DSC configuration in `examples/dsc_configuration.ps1`, then:

```yaml
---
driver:
  name: vagrant

provisioner:
  name: dsc
  dsc_local_configuration_manager_version: wmf5

platforms:
  - name: windows-2022

suites:
  - name: default
```

Then run the full test cycle:

```sh
cinc kitchen test
```

Or step through it:

```sh
cinc kitchen create    # build the Windows instance
cinc kitchen converge  # apply the DSC configuration
cinc kitchen verify    # run your tests
cinc kitchen destroy   # remove the instance
```

By default the provisioner looks for a configuration named after the suite, in
`examples/dsc_configuration.ps1`.

> **Note on output timing:** the verbose stream is returned after the DSC job
> completes rather than while it runs, because WMF versions differ in how they
> expose that stream. Expect a delay before you see run details.

## How it works

Knowing the sequence makes the configuration options below much easier to
place, and it is what you need when a converge fails partway through.

1. **Configure the LCM.** During `kitchen converge`, before anything is
   compiled, the provisioner generates a `SetupLCM` meta-configuration from
   `dsc_local_configuration_manager_version` and
   `dsc_local_configuration_manager` and applies it with
   `Set-DscLocalConfigurationManager`. The LCM governs how DSC behaves for the
   rest of the run, so it is set first.
2. **Prepare the instance.** A directory for the configuration script is
   created on the instance. On WMF 5, anything in `modules_from_gallery` is
   installed at this point, bootstrapping the NuGet package provider and
   registering `gallery_uri` first if needed.
3. **Stage files on your workstation.** DSC resources and the configuration
   script are copied into a sandbox directory, which Test Kitchen then uploads
   to `root_path` on the instance. Which files get staged depends on the
   project layout — see [Two ways to lay out a
   project](#two-ways-to-lay-out-a-project).
4. **Compile the MOF.** On the instance, the uploaded `modules` directory is
   copied onto the `PSModulePath`, the configuration script is loaded, and each
   name in `configuration_name` is compiled into
   `C:\configurations\<name>`. Any MOF left over from a previous converge is
   removed first, so a failed compile cannot be silently reapplied.
5. **Apply it.** `Start-DscConfiguration` runs against each compiled MOF. If
   DSC reports that a reboot is required, the instance reboots and the converge
   exits 35, which Test Kitchen retries — see [Reboot
   handling](#reboot-handling).

`cinc kitchen verify` then runs whatever verifier you configured. This
provisioner does not verify anything itself.

## Configuration

All options below are set under the `provisioner:` key in `kitchen.yml`, or per suite under `suites[].provisioner:`.

To see how any of them resolved for a given instance — including the LCM
settings, which are filled in from the defaults below — run
`cinc kitchen diagnose <instance>`.

### Configuration script

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `configuration_script_folder` | String | `"examples"` | Directory holding the PowerShell script(s) that define the DSC configuration, relative to the directory holding `kitchen.yml`. |
| `configuration_script` | String | `"dsc_configuration.ps1"` | Name of the PowerShell script containing the DSC configuration command, and possibly its configuration data. |
| `configuration_name` | String or Array&lt;String&gt; | the suite name | Name of the configuration command to run. Give an array to compile and apply several from one script. |

### Configuration data

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `configuration_data` | Hash | *unset* | YAML representation of the data passed to the configuration. Overrides any configuration data assigned in the script itself. Rendered into a PowerShell hashtable, with every scalar quoted as a string. |
| `configuration_data_variable` | String | `"ConfigurationData"` | Name of the variable holding the ConfigurationData hashtable. Can be set here or defined in the configuration script. |

### Local Configuration Manager

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `dsc_local_configuration_manager_version` | String | `"wmf4"` | Which LCM is in place. Also accepts `wmf4_with_update` and `wmf5`. Any other value falls back to the base WMF 4 settings without warning. |
| `dsc_local_configuration_manager` | Hash | *see below* | Hash of LCM settings. Anything you leave out is filled in from the defaults for the version above. |

`wmf4_with_update` means WMF 4 with KB3000850 applied, which adds support for
configurations generated by WMF 5 along with a number of fixes. Today the only
differences between `wmf4` and the other two values are the `action_after_reboot`
and `debug_mode` settings.

The LCM settings and their defaults:

| Setting | Type | Default | Notes |
| --- | --- | --- | --- |
| `action_after_reboot` | String | `"StopConfiguration"` | `wmf4_with_update` and `wmf5` only. |
| `reboot_if_needed` | Boolean | `false` | |
| `allow_module_overwrite` | Boolean | `false` | |
| `certificate_id` | String | `nil` | Rendered as `$null` when unset. |
| `configuration_mode` | String | `"ApplyAndAutoCorrect"` | |
| `configuration_mode_frequency_mins` | Integer | `30` | `15` on `wmf5`. |
| `debug_mode` | String | `"All"` | `wmf4_with_update` and `wmf5` only. |
| `refresh_frequency_mins` | Integer | `15` | `30` on `wmf5`. |
| `refresh_mode` | String | `"PUSH"` | |

### Modules from a gallery

Installing modules from a gallery requires WMF 5 on the instance.

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `modules_from_gallery` | String, Array, or Array&lt;Hash&gt; | *unset* | Modules to install from a gallery. A string for one module, an array for several, or a hash matching the parameters of `Install-Module`. `Name` is required; `Force` is always applied and need not be given. Ignored unless `dsc_local_configuration_manager_version` is `wmf5`. |
| `gallery_name` | String | *unset* | Name of a custom PowerShell gallery to install from. If no package source with this name is registered on the machine, `gallery_uri` must be set too. Defaults to `PSGallery` when neither is given, and to `testing` when only `gallery_uri` is. |
| `gallery_uri` | String | *unset* | URI of a custom PowerShell gallery feed. Registered as a trusted package source before any module is installed. |
| `nuget_force_bootstrap` | Boolean | `true` | Bootstrap the NuGet package provider for PowerShell PackageManagement before installing modules. |

### Repository style testing

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `modules_path` | String | `"modules"` | Directory of modules containing DSC resources to upload to the instance, relative to the root of the repository, next to `kitchen.yml`. A missing directory is not an error — the converge just carries on with whatever resources the instance already has. |

### Reboot handling

These are standard Test Kitchen provisioner options that this provisioner gives DSC-specific defaults.

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `retry_on_exit_code` | Array&lt;Integer&gt; | `[35]` | Exit codes that cause the converge to be retried. Exit code 35 is DSC signalling that a reboot is required. Set it yourself and this provisioner leaves it alone. |
| `max_retries` | Integer | `3` | Number of times to retry the converge on one of those exit codes. Only defaulted to `3` if you left it at Test Kitchen's default of `1`. |
| `root_path` | String | transport default | Directory on the instance where the configuration and modules are staged. |

## Examples

### Module style, with modules from a custom gallery

```yaml
provisioner:
  name: dsc
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

suites:
  - name: test
    provisioner:
      configuration_data:
        AllNodes:
          - nodename: localhost
            role: webserver
```

### Repository style

```yaml
provisioner:
  name: dsc
  dsc_local_configuration_manager_version: wmf5
  modules_path: modules
  configuration_script_folder: examples
  configuration_script: webserver.ps1
  configuration_name: WebServer
```

### Allowing reboots during a converge

```yaml
provisioner:
  name: dsc
  dsc_local_configuration_manager_version: wmf5
  dsc_local_configuration_manager:
    reboot_if_needed: true
    action_after_reboot: ContinueConfiguration
  max_retries: 5
```

### Per-suite configuration data

```yaml
provisioner:
  name: dsc
  configuration_script_folder: examples
  configuration_script: webserver.ps1

suites:
  - name: default
    provisioner:
      configuration_data:
        AllNodes:
          - nodename: localhost
            role: webserver
  - name: minimal
    provisioner:
      configuration_data:
        AllNodes:
          - nodename: localhost
            role: minimal
```

## Using with Chef

This provisioner is not tied to Cinc, and it does not require Cinc or Chef on the instance at all — it applies DSC configurations directly. The commands above use Cinc Workstation; with [Chef Workstation](https://www.chef.io/downloads/tools/workstation) run `kitchen` instead of `cinc kitchen`. No provisioner configuration changes are needed.

## Troubleshooting

**`No such file or directory` before the instance is even touched.** The
configuration script was not found on your workstation. It is looked for at
`<configuration_script_folder>/<configuration_script>`, relative to the
directory holding `kitchen.yml` — by default `examples/dsc_configuration.ps1`.

**`Failed to find <path>`.** The configuration script was staged locally but
did not arrive on the instance, so the upload is what failed. Check that
`root_path` is somewhere the transport's account can write.

**`Failed to create a configuration command <name>`.** The script loaded, but
running it defined no configuration by that name. `configuration_name` must
match the name after the `Configuration` keyword in the script; it defaults to
the *suite* name, which is rarely what you want once the script names its
configuration something meaningful.

**The compile fails on an unknown DSC resource.** The resource never reached
the instance's `PSModulePath`. For repository style, check that
your resources are under `modules_path` and that each one is its own directory
with a module manifest — the provisioner copies the *directories* inside that
path, not loose files.

**Module style is not being detected.** The kitchen root is only treated as a
PowerShell module when it contains `<directory name>.psd1` — that is, a
manifest named after the *directory you cloned into*. Clone `xWebAdministration`
into a folder called `webadmin` and the manifest no longer matches, so the
provisioner silently falls back to repository style.

**`modules_from_gallery` is quietly ignored.** Gallery installation needs
PowerShellGet, so it only runs when
`dsc_local_configuration_manager_version` is exactly `wmf5`. On `wmf4` or
`wmf4_with_update` nothing is installed and nothing is logged about it.

**`Unable to find repository '<name>'`.** `gallery_name` on its own only works
if that package source is already registered on the instance. Set `gallery_uri`
as well and the provisioner will register it for you.

**The converge reboots in a loop.** A resource keeps asking for a reboot. The
provisioner exits 35 and Test Kitchen retries up to `max_retries` times; if the
resource is never satisfied, that becomes a loop. Set
`dsc_local_configuration_manager.reboot_if_needed: true` and
`action_after_reboot: ContinueConfiguration` so DSC resumes on its own instead.

**No output until the configuration finishes.** Expected — see the note in
[Quick Start](#quick-start). The verbose stream is collected from the DSC job
after it completes.

**Anything else.** Two commands cover most of it:

```sh
cinc kitchen diagnose default-windows-2022   # the fully resolved configuration
cinc kitchen converge default-windows-2022 -l debug
```

The debug log contains the exact PowerShell this provisioner generated for each
phase, which is usually enough to see what went wrong. To reproduce a failure
by hand, log into the instance with `cinc kitchen login` and run the compile
step yourself from `C:\configurations\<configuration_name>`.

## Contributing

This project has no active maintainers, so please read the status note at the
top before opening an issue. Pull requests are still welcome on
[GitHub](https://github.com/test-kitchen/kitchen-dsc). See
[CONTRIBUTING.md](CONTRIBUTING.md) for development setup and the state of the
test tooling.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
