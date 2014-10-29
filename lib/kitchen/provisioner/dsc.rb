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
require 'pry'

module Kitchen
  class Busser
     def setup_cmd
      return if local_suite_files.empty?
      ruby    = "#{config[:ruby_bindir]}/ruby"
      gem     = sudo("#{config[:ruby_bindir]}/gem")
      busser  = sudo(config[:busser_bin])

      ## Need to parameterize this (for the cache location...)
      case shell
      when "powershell"
        cmd = <<-CMD.gsub(/^ {10}/, "")
          cd c:\\vagrant
          #{busser_setup_env}
          if ((gem list busser -i) -eq \"false\") {
            gem install #{gem_install_args}
          }
          # We have to modify Busser::Setup to work with PowerShell
          # busser setup
          #{busser} plugin install #{plugins.join(" ")}
        CMD
      else
        raise "[#{self}] Unsupported shell: #{shell}"
      end
      Util.wrap_command(cmd, shell)
    end

    def non_suite_dirs
      %w(modules chef_installer configuration_data)
    end
  end

  module Provisioner
    class Dsc < Base
      attr_accessor :tmp_dir

      default_config :modules_path, 'modules'
      default_config :configuration_script, 'dsc_configuration.ps1'
      default_config :require_chef_omnibus, true      
      default_config :chef_installer_path, 'c:\tmp\kitchen\chef_installer\chef.msi'
      default_config :chef_omnibus_url, 'https://www.getchef.com/chef/install.sh'

      def install_command
        return unless config[:require_chef_omnibus]
        info('Installing chef-client to allow bussers to run.')
        debug('I should really find another way to make this work.')

        lines = [Util.shell_helpers(shell), chef_shell_helpers, chef_install_function]
        Util.wrap_command(lines.join("\n"), shell)
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

          dir 'c:/tmp/kitchen/modules/*' -directory |
            copy-item -destination $env:programfiles/windowspowershell/modules/ -recurse -force

          . c:/tmp/kitchen/#{config[:configuration_script]}
          #{current_configuration} -outputpath c:/tmp/kitchen/configurations | out-null

        EOH

        Util.wrap_command(stage_resources_and_generate_mof_script, shell)
      end

      def run_command
        info("Running the configuration #{current_configuration}")
        run_configuration_script = <<-EOH

          $job = start-dscconfiguration -Path c:/tmp/kitchen/configurations/
          $job | wait-job
          $job.childjobs[0].verbose

        EOH
        Util.wrap_command(run_configuration_script, shell)
      end

      def current_configuration
        run_list = config[:run_list] ? @instance.suite.name : config[:run_list][0]
      end

      # copied wholesale from chef_base
      # there's got to be a better way!
      def chef_shell_helpers
        case shell
        when 'bourne'
          file = 'chef_helpers.sh'
        when 'powershell'
          file = 'chef_helpers.ps1'
        else
          fail "[chef_shell_helpers] Unsupported shell: #{shell}"
        end

        IO.read(File.join(
          File.dirname(__FILE__), %W(.. .. .. support #{file})
        )).gsub(/\\n/, "\n")
      end

      def chef_install_function
        case shell
        when 'bourne'
          version = config[:require_chef_omnibus].to_s.downcase
          pretty_version = case version
                           when 'true' then 'install only if missing'
                           when 'latest' then 'always install latest version'
                           else version
                           end
          install_flags = %w(latest true).include?(version) ? '' : "-v #{version}"

          <<-INSTALL.gsub(/^ {10}/, '')
            if should_update_chef "/opt/chef" "#{version}" ; then
              echo "-----> Installing Chef Omnibus (#{pretty_version})"
              do_download #{config[:chef_omnibus_url]} /tmp/install.sh
              #{sudo('sh')} /tmp/install.sh #{install_flags}
            else
              echo "-----> Chef Omnibus installation detected (#{pretty_version})"
            fi
          INSTALL
        when 'powershell'
          version = config[:require_chef_omnibus].to_s.downcase
          install_flags = %w(latest true).include?(version) ? '' : "v=#{version}"

          # If we have the default URL for UNIX then we change it for the Windows version.
          if config[:chef_omnibus_url] =~ %r{http[s]*://www.getchef.com/chef/install.sh}
            chef_url = "http://www.getchef.com/chef/install.msi?#{install_flags}"
          else
            # We use the one that comes from kitchen.yml
            chef_url = "#{config[:chef_omnibus_url]}?#{install_flags}"
          end

          # NOTE We use SYSTEMDRIVE because if we use TEMP the installation fails.
          <<-INSTALL.gsub(/^ {10}/, '')
            
            $chef_msi = join-path $env:SYSTEMDRIVE 'chef.msi'
            $chef_installer_directory = split-path $chef_msi

            $starting_chef_msi = '#{config[:chef_installer_path]}'
            if (test-path $starting_chef_msi) {
              copy-item $starting_chef_msi -destination $chef_msi
            }
            
            If (should_update_chef #{version}) {
              Write-Host "-----> Installing Chef Omnibus (#{version})\n"
              if (-not (test-path $chef_msi)) {
                download_chef "#{chef_url}" $chef_msi
              }
              else {
                Write-Host "-----> Chef client installer detected, skipping download.\n"
              }
              install_chef
            } else {
              Write-Host "-----> Chef Omnibus installation detected (#{version})\n"
            }
          INSTALL
        else
          fail "[chef_install_function] Unsupported shell: #{shell}"
        end
      end
    end
  end
end
