# frozen_string_literal: true

RSpec.describe Kitchen::Provisioner::Dsc do
  subject(:provisioner) { build_provisioner }

  # Every public command is wrapped by Kitchen::Configurable#wrap_shell_code,
  # which injects `$env:TEST_KITCHEN` and — only when ENV["CI"] is set —
  # `$env:CI`. Specs therefore assert on the PowerShell that this gem generates
  # rather than on whole-string equality, so they behave the same on a laptop
  # and on a runner.

  describe "plugin registration" do
    it "declares provisioner API version 2" do
      expect(provisioner.diagnose_plugin[:api_version]).to eq(2)
    end

    it "exposes a writable tmp_dir" do
      provisioner.tmp_dir = 'C:\\temp'

      expect(provisioner.tmp_dir).to eq('C:\\temp')
    end
  end

  describe "default configuration" do
    it "stages configuration scripts out of examples/" do
      expect(provisioner[:configuration_script_folder]).to eq("examples")
      expect(provisioner[:configuration_script]).to eq("dsc_configuration.ps1")
    end

    it "looks for DSC resources under modules/" do
      expect(provisioner[:modules_path]).to eq("modules")
    end

    it "targets WMF 4 and force-bootstraps NuGet" do
      expect(provisioner[:dsc_local_configuration_manager_version]).to eq("wmf4")
      expect(provisioner[:nuget_force_bootstrap]).to be(true)
    end

    context "when the suite is named" do
      def suite_name
        "webserver"
      end

      it "derives the configuration name from the suite" do
        expect(provisioner[:configuration_name]).to eq(["webserver"])
      end
    end
  end

  describe "#finalize_config!" do
    # finalize_config! is called for us when KitchenHelpers builds the
    # instance, so the merged LCM settings are already on config by this point.

    it "replaces the LCM config with the resolved settings" do
      expect(provisioner[:dsc_local_configuration_manager]).to include(
        allow_module_overwrite: false,
        configuration_mode: "ApplyAndAutoCorrect",
        configuration_mode_frequency_mins: 30,
        reboot_if_needed: false,
        refresh_mode: "PUSH",
        refresh_frequency_mins: 15
      )
    end

    it "renders an unset certificate_id as a PowerShell null" do
      expect(provisioner[:dsc_local_configuration_manager][:certificate_id]).to eq("$null")
    end

    it "keeps caller-supplied LCM settings" do
      provisioner = build_provisioner(
        dsc_local_configuration_manager: {
          configuration_mode: "ApplyOnly",
          reboot_if_needed: true,
        }
      )

      expect(provisioner[:dsc_local_configuration_manager]).to include(
        configuration_mode: "ApplyOnly",
        reboot_if_needed: true
      )
    end

    context "when targeting WMF 5" do
      subject(:provisioner) { build_provisioner(dsc_local_configuration_manager_version: "wmf5") }

      it "uses the WMF 5 defaults and settings" do
        expect(provisioner[:dsc_local_configuration_manager]).to include(
          action_after_reboot: "StopConfiguration",
          debug_mode: "All",
          configuration_mode_frequency_mins: 15,
          refresh_frequency_mins: 30
        )
      end
    end
  end

  describe "#install_command" do
    subject(:command) { provisioner.install_command }

    it "silences the PowerShell progress stream" do
      expect(command).to include("$ProgressPreference = 'SilentlyContinue';")
    end

    it "declares and applies the SetupLCM configuration" do
      expect(command).to include("configuration SetupLCM")
      expect(command).to include("$null = SetupLCM")
      expect(command).to include("Set-DscLocalConfigurationManager -Path ./SetupLCM | out-null")
    end

    it "emits the resolved LCM settings" do
      expect(command).to include("AllowModuleOverwrite = [bool]::Parse('false')")
      expect(command).to include("ConfigurationMode = 'ApplyAndAutoCorrect'")
      expect(command).to include("RefreshMode = 'PUSH'")
      expect(command).to include("CertificateID = $null")
    end

    context "with a certificate thumbprint" do
      subject(:provisioner) do
        build_provisioner(dsc_local_configuration_manager: { certificate_id: "ABC123" })
      end

      it "single-quotes the thumbprint" do
        expect(command).to include("CertificateID = 'ABC123'")
      end
    end

    context "when targeting WMF 5" do
      subject(:provisioner) { build_provisioner(dsc_local_configuration_manager_version: "wmf5") }

      it "emits the WMF 5 meta-configuration" do
        expect(command).to include("[DSCLocalConfigurationManager()]")
        expect(command).to include("ActionAfterReboot = 'StopConfiguration'")
        expect(command).to include("DebugMode = 'All'")
      end
    end

    context "when the LCM version is unrecognized" do
      subject(:provisioner) { build_provisioner(dsc_local_configuration_manager_version: "wmf9000") }

      # DscLcmConfiguration::Factory falls through to LcmBase for anything it
      # does not recognize — including the "wmf4" default this gem ships.
      it "falls back to the base LCM configuration" do
        expect(command).to include("LocalConfigurationManager")
        expect(command).not_to include("ActionAfterReboot")
      end
    end
  end

  describe "#init_command" do
    subject(:command) { provisioner.init_command }

    it "creates the remote configuration directory" do
      expect(command).to include(
        "mkdir (split-path (join-path #{KitchenHelpers::DEFAULT_ROOT_PATH} " \
        "configuration/dsc_configuration.ps1)) -force | out-null"
      )
    end

    context "on WMF 4 with gallery modules requested" do
      subject(:provisioner) { build_provisioner(modules_from_gallery: %w{xNetworking}) }

      # Gallery installation needs PowerShellGet, which ships with WMF 5.
      it "does not attempt to install them" do
        expect(command).not_to include("install-module")
        expect(command).not_to include("install-packageprovider")
      end
    end

    context "on WMF 5 without gallery modules" do
      subject(:provisioner) { build_provisioner(dsc_local_configuration_manager_version: "wmf5") }

      it "does not attempt to install anything" do
        expect(command).not_to include("install-module")
      end
    end

    context "on WMF 5 with gallery modules" do
      subject(:provisioner) do
        build_provisioner(
          dsc_local_configuration_manager_version: "wmf5",
          modules_from_gallery: %w{xNetworking xWebAdministration}
        )
      end

      it "bootstraps the NuGet package provider" do
        expect(command).to include("install-packageprovider nuget -force -forcebootstrap | out-null")
      end

      it "installs each module from the default gallery" do
        expect(command).to include("install-module -name 'xNetworking' -Repository PSGallery -force | out-null")
        expect(command).to include("install-module -name 'xWebAdministration' -Repository PSGallery -force | out-null")
      end

      it "does not register a repository when no gallery_uri is given" do
        expect(command).not_to include("register-packagesource")
      end

      context "with nuget_force_bootstrap disabled" do
        subject(:provisioner) do
          build_provisioner(
            dsc_local_configuration_manager_version: "wmf5",
            modules_from_gallery: %w{xNetworking},
            nuget_force_bootstrap: false
          )
        end

        it "skips the package provider bootstrap" do
          expect(command).not_to include("install-packageprovider")
        end
      end

      context "with a private gallery_uri and no gallery_name" do
        subject(:provisioner) do
          build_provisioner(
            dsc_local_configuration_manager_version: "wmf5",
            modules_from_gallery: %w{xNetworking},
            gallery_uri: "https://gallery.example.invalid/api/v2"
          )
        end

        it "registers the source under the fallback name 'testing'" do
          expect(command).to include(
            "register-packagesource -providername PowerShellGet -name 'testing' " \
            "-location 'https://gallery.example.invalid/api/v2' -force -trusted"
          )
        end

        it "installs modules from that source" do
          expect(command).to include("install-module -name 'xNetworking' -Repository testing -force | out-null")
        end
      end

      context "with a named private gallery" do
        subject(:provisioner) do
          build_provisioner(
            dsc_local_configuration_manager_version: "wmf5",
            modules_from_gallery: %w{xNetworking},
            gallery_uri: "https://gallery.example.invalid/api/v2",
            gallery_name: "Internal"
          )
        end

        it "registers and installs under the given name" do
          expect(command).to include("-name 'Internal'")
          expect(command).to include("install-module -name 'xNetworking' -Repository Internal -force | out-null")
        end
      end

      context "when a module is given as a specification hash" do
        subject(:provisioner) do
          build_provisioner(
            dsc_local_configuration_manager_version: "wmf5",
            modules_from_gallery: [{ "Name" => "xWebAdministration", "RequiredVersion" => "1.10.0.0" }]
          )
        end

        it "passes each key through as a PowerShell parameter" do
          expect(command).to include("install-module -Name xWebAdministration -RequiredVersion 1.10.0.0")
        end

        it "defaults the repository to the resolved gallery" do
          expect(command).to include("-repository PSGallery")
        end
      end

      context "when a module specification sets its own repository" do
        subject(:provisioner) do
          build_provisioner(
            dsc_local_configuration_manager_version: "wmf5",
            gallery_name: "Internal",
            gallery_uri: "https://gallery.example.invalid/api/v2",
            modules_from_gallery: [{ "Name" => "xWebAdministration", "Repository" => "Other" }]
          )
        end

        it "does not override it with the configured gallery" do
          expect(command).to include("-Repository Other")
          expect(command).not_to include("-repository Internal")
        end
      end

      context "when a module specification passes Force" do
        subject(:provisioner) do
          build_provisioner(
            dsc_local_configuration_manager_version: "wmf5",
            modules_from_gallery: [{ "Name" => "xWebAdministration", "Force" => true }]
          )
        end

        # -force is already appended to every install-module call; passing it
        # twice is a PowerShell parameter-binding error.
        it "drops it rather than emitting -Force twice" do
          expect(command).to include("install-module -Name xWebAdministration -repository PSGallery -force")
          expect(command).not_to include("-Force true")
        end
      end

      context "when the repository is defaulted into a module specification" do
        subject(:provisioner) do
          build_provisioner(
            dsc_local_configuration_manager_version: "wmf5",
            modules_from_gallery: [{ "Name" => "xWebAdministration" }]
          )
        end

        # The hash is the user's own entry in config[:modules_from_gallery].
        # Writing the resolved repository back into it would leave
        # `kitchen diagnose` reporting a setting they never wrote.
        it "does not write the resolved repository back into the user's config" do
          command

          expect(provisioner[:modules_from_gallery]).to eq([{ "Name" => "xWebAdministration" }])
        end

        it "still emits the same command when built twice" do
          expect(provisioner.init_command).to eq(command)
        end
      end
    end
  end

  describe "#create_sandbox" do
    let(:sandbox) { create_sandbox_for(provisioner) }

    before { write_kitchen_file("examples/dsc_configuration.ps1", "configuration default {}\n") }

    it "stages the configuration script under configuration/" do
      expect(File.read(File.join(sandbox, "configuration/dsc_configuration.ps1")))
        .to eq("configuration default {}\n")
    end

    it "logs what it is staging" do
      sandbox

      expect(kitchen_log).to include("Staging DSC Resource Modules for copy to the SUT")
      expect(kitchen_log).to include("Staging DSC configuration script for copy to the SUT")
    end

    context "with a custom configuration script location" do
      subject(:provisioner) do
        build_provisioner(
          configuration_script_folder: "dsc",
          configuration_script: "web.ps1"
        )
      end

      before { write_kitchen_file("dsc/web.ps1", "configuration web {}\n") }

      it "stages it under its own name" do
        expect(File.read(File.join(sandbox, "configuration/web.ps1"))).to eq("configuration web {}\n")
      end
    end

    context "when the configuration script is missing" do
      subject(:provisioner) { build_provisioner(configuration_script: "absent.ps1") }

      it "fails loudly rather than staging an empty sandbox" do
        expect { create_sandbox_for(provisioner) }.to raise_error(Errno::ENOENT, /absent\.ps1/)
      end
    end

    context "with a repository-style layout" do
      before do
        write_kitchen_file("modules/xExample/xExample.psd1")
        write_kitchen_file("modules/xExample/DSCResources/xThing/xThing.psm1")
      end

      it "copies the modules directory into the sandbox" do
        expect(files_under(File.join(sandbox, "modules"))).to contain_exactly(
          "xExample/xExample.psd1",
          "xExample/DSCResources/xThing/xThing.psm1"
        )
      end

      context "and a custom modules_path" do
        subject(:provisioner) { build_provisioner(modules_path: "dsc_resources") }

        before { write_kitchen_file("dsc_resources/xOther/xOther.psd1") }

        it "copies from that path instead" do
          expect(files_under(File.join(sandbox, "modules"))).to include("xOther/xOther.psd1")
        end
      end

      context "and no modules directory at all" do
        subject(:provisioner) { build_provisioner(modules_path: "does_not_exist") }

        it "stages the configuration script anyway" do
          expect(File).to exist(File.join(sandbox, "configuration/dsc_configuration.ps1"))
        end

        it "says why it skipped the copy" do
          sandbox

          expect(kitchen_log).to include("was not found. Not moving to")
        end
      end
    end

    context "with a module-style layout" do
      # A <root>/<basename>.psd1 manifest is what flips the provisioner from
      # repository style to module style.
      let(:module_name) { File.basename(kitchen_root) }

      before do
        write_kitchen_file("#{module_name}.psd1", "@{ ModuleVersion = '1.0' }\n")
        write_kitchen_file("#{module_name}.psm1", "function Get-Thing {}\n")
        write_kitchen_file("DSCResources/xThing/xThing.psm1")
        write_kitchen_file("Gemfile", "source 'https://rubygems.org'\n")
        write_kitchen_file("Gemfile.lock", "DEPENDENCIES\n")
        write_kitchen_file("README.md", "# docs\n")
        write_kitchen_file("LICENSE.txt", "Apache-2.0\n")
      end

      it "stages the whole module under modules/<module name>" do
        expect(files_under(File.join(sandbox, "modules", module_name))).to contain_exactly(
          "#{module_name}.psd1",
          "#{module_name}.psm1",
          "DSCResources/xThing/xThing.psm1",
          "examples/dsc_configuration.ps1"
        )
      end

      it "leaves repository housekeeping files behind" do
        staged = files_under(File.join(sandbox, "modules", module_name))

        expect(staged).not_to include("Gemfile", "Gemfile.lock", "README.md", "LICENSE.txt")
      end
    end
  end

  describe "#prepare_command" do
    subject(:command) { provisioner.prepare_command }

    it "copies staged modules onto the PSModulePath" do
      expect(command).to include("if (Test-Path (join-path #{KitchenHelpers::DEFAULT_ROOT_PATH} 'modules'))")
      expect(command).to include("copy-item -destination $env:programfiles/windowspowershell/modules/ -recurse -force")
    end

    it "fails on the SUT when the configuration script did not arrive" do
      expect(command).to include('throw "Failed to find $ConfigurationScriptPath"')
    end

    it "dot-sources the configuration script" do
      expect(command).to include("invoke-expression (get-content $ConfigurationScriptPath -raw)")
    end

    it "clears $Error and compiles the MOF for the suite's configuration" do
      expect(command).to include("$Error.clear()")
      expect(command).to include("$null = default -outputpath c:/configurations/default")
    end

    it "removes any MOF left over from a previous converge" do
      expect(command).to include("Remove-Item -Recurse -Force c:/configurations/default")
    end

    it "fails when the configuration command was never defined" do
      expect(command).to include('throw "Failed to create a configuration command default"')
    end

    it "logs the configuration it is compiling" do
      command

      expect(kitchen_log).to include("Generating the MOF script for the configuration default")
    end

    context "with several configuration names" do
      subject(:provisioner) { build_provisioner(configuration_name: %w{web database}) }

      it "emits a compile block per configuration" do
        expect(command).to include("$null = web -outputpath c:/configurations/web")
        expect(command).to include("$null = database -outputpath c:/configurations/database")
      end
    end

    context "with a single configuration name given as a string" do
      subject(:provisioner) { build_provisioner(configuration_name: "web") }

      it "treats it as a one-element list" do
        expect(command).to include("$null = web -outputpath c:/configurations/web")
      end
    end

    context "with configuration data" do
      subject(:provisioner) do
        build_provisioner(
          configuration_data: {
            "AllNodes" => [{ "NodeName" => "*", "PSDscAllowPlainTextPassword" => true }],
          }
        )
      end

      it "assigns it to a PowerShell hashtable before compiling" do
        expect(command).to include("$ConfigurationData = @{")
        expect(command).to include('"AllNodes" =')
        expect(command).to include('"NodeName" = "*"')
      end

      it "renders nested arrays as PowerShell arrays" do
        expect(command).to include("@(")
      end

      # ps_hash stringifies every scalar, so Ruby booleans reach DSC quoted.
      it "renders booleans as quoted strings" do
        expect(command).to include('"PSDscAllowPlainTextPassword" = "true"')
      end

      it "passes the hashtable to the configuration" do
        expect(command).to include("-configurationdata $ConfigurationData")
      end

      # ps_hash renders scalars into PowerShell double-quoted strings, where a
      # backtick escapes, a dollar sign interpolates and a double quote ends
      # the string. Unescaped, `P@$$w0rd` reaches DSC as `P@w0rd` and a value
      # containing a quote breaks the generated script outright.
      context "with PowerShell metacharacters in the data" do
        subject(:provisioner) do
          build_provisioner(
            configuration_data: {
              "AllNodes" => [{
                "NodeName" => "*",
                "Password" => "P@$$w0rd",
                "Home" => "$env:USERPROFILE",
                "Quoted" => 'he said "hi"',
                "Backtick" => 'C:\tmp`x',
              }],
            }
          )
        end

        it "escapes a dollar sign so the value is not interpolated away" do
          expect(command).to include('"Password" = "P@`$`$w0rd"')
        end

        it "escapes a variable reference rather than expanding it on the SUT" do
          expect(command).to include('"Home" = "`$env:USERPROFILE"')
        end

        it "escapes a double quote so the string is not terminated early" do
          expect(command).to include('"Quoted" = "he said `"hi`""')
        end

        it "escapes a literal backtick" do
          expect(command).to include('"Backtick" = "C:\tmp``x"')
        end

        it "leaves a key containing no metacharacters alone" do
          expect(command).to include('"NodeName" = "*"')
        end
      end

      context "with PowerShell metacharacters in a key" do
        subject(:provisioner) do
          build_provisioner(configuration_data: { 'Odd"$Key' => "value" })
        end

        it "escapes the key too" do
          expect(command).to include('"Odd`"`$Key" = "value"')
        end
      end

      # `configuration_data_variable:` with an empty value in kitchen.yml parses
      # as nil, which must not produce a bare `$` in the generated script.
      context "with the variable name explicitly blanked out" do
        subject(:provisioner) do
          build_provisioner(
            configuration_data: { "AllNodes" => [] },
            configuration_data_variable: nil
          )
        end

        it "falls back to $ConfigurationData" do
          expect(command).to include("$ConfigurationData = @{")
          expect(command).to include("-configurationdata $ConfigurationData")
        end
      end

      context "under a custom variable name" do
        subject(:provisioner) do
          build_provisioner(
            configuration_data: { "AllNodes" => [] },
            configuration_data_variable: "MyData"
          )
        end

        it "assigns and passes that variable" do
          expect(command).to include("$MyData = @{")
          expect(command).to include("-configurationdata $MyData")
        end
      end
    end

    context "without configuration data" do
      it "assigns nothing" do
        expect(command).not_to include("$ConfigurationData = @{")
      end

      # Known wart: the -configurationdata argument is emitted unconditionally,
      # so the compile references an undefined variable. DSC tolerates it
      # because $null is a valid ConfigurationData value.
      it "still passes the (undefined) configuration data variable" do
        expect(command).to include("-configurationdata $ConfigurationData")
      end
    end
  end

  describe "#run_command" do
    subject(:command) { provisioner.run_command }

    it "starts and waits on the DSC configuration job" do
      expect(command).to include("$job = start-dscconfiguration -Path c:/configurations/default -force")
      expect(command).to include("$job | wait-job")
    end

    it "surfaces the job's verbose stream" do
      expect(command).to include("$verbose_output = $job.childjobs[0].verbose")
    end

    it "reboots and exits 35 when DSC asks for a reboot" do
      expect(command).to include("shutdown /r /t 15")
      expect(command).to include("exit 35")
    end

    it "exits non-zero when the job reported errors" do
      expect(command).to include("$dsc_errors = $job.childjobs[0].Error")
      expect(command).to include("exit 1")
    end

    it "logs the configuration it is applying" do
      command

      expect(kitchen_log).to include("Running the configuration default")
    end

    it "retries on the reboot exit code" do
      command

      expect(provisioner[:retry_on_exit_code]).to eq([35])
      expect(provisioner[:max_retries]).to eq(3)
    end

    context "when the user configured their own retry behaviour" do
      subject(:provisioner) { build_provisioner(retry_on_exit_code: [1, 2], max_retries: 5) }

      it "leaves it alone" do
        command

        expect(provisioner[:retry_on_exit_code]).to eq([1, 2])
        expect(provisioner[:max_retries]).to eq(5)
      end
    end

    context "with several configuration names" do
      subject(:provisioner) { build_provisioner(configuration_name: %w{web database}) }

      it "applies each configuration in turn" do
        expect(command).to include("start-dscconfiguration -Path c:/configurations/web -force")
        expect(command).to include("start-dscconfiguration -Path c:/configurations/database -force")
      end
    end
  end
end
