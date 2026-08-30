#Requires -Version 5
<#
.SYNOPSIS
    Asserts that the kitchen-dsc integration suite actually converged.

.DESCRIPTION
    Run by the shell verifier after `kitchen converge`. The GitHub runner is
    both the workstation and the system under test, so this executes locally
    against the machine DSC just configured. Every check maps to one thing
    kitchen-dsc is responsible for, so a failure names the phase that broke.
#>
[CmdletBinding()]
param (
    [string] $TargetPath = 'C:\kitchen-dsc-integration',
    [string] $Marker = 'staged-by-kitchen-dsc',
    [string] $ModuleName = 'KitchenDscExample'
)

$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()

function Assert-KitchenDsc
{
    param (
        [Parameter(Mandatory)] [string] $Description,
        [Parameter(Mandatory)] [scriptblock] $Condition
    )

    $result = $false
    try
    {
        $result = [bool] (& $Condition)
    }
    catch
    {
        $script:failures.Add("$Description -- threw: $($_.Exception.Message)")
        Write-Host "FAIL $Description"
        return
    }

    if ($result)
    {
        Write-Host "PASS $Description"
    }
    else
    {
        $script:failures.Add($Description)
        Write-Host "FAIL $Description"
    }
}

# install_command: the LCM meta-configuration was compiled and applied.
$lcm = Get-DscLocalConfigurationManager
Assert-KitchenDsc 'the LCM refresh mode was set to Push' { $lcm.RefreshMode -eq 'Push' }
Assert-KitchenDsc 'the LCM configuration mode was set to ApplyAndAutoCorrect' {
    $lcm.ConfigurationMode -eq 'ApplyAndAutoCorrect'
}

# create_sandbox + prepare_command: modules_path was staged and copied onto the
# PSModulePath of the system under test.
Assert-KitchenDsc "the $ModuleName module reached the PSModulePath" {
    $null -ne (Get-Module -ListAvailable -Name $ModuleName)
}
Assert-KitchenDsc "the $ModuleName module is loadable and exports its function" {
    Import-Module $ModuleName -Force
    (Get-KitchenDscExampleMarker) -eq $Marker
}

# prepare_command: the configuration script was uploaded and compiled to a MOF.
Assert-KitchenDsc 'the configuration compiled to a MOF' {
    Test-Path -Path 'C:\configurations\KitchenDscTest\localhost.mof'
}

# run_command: Start-DscConfiguration applied the compiled MOF.
$testFile = Join-Path -Path $TargetPath -ChildPath 'kitchen-dsc.txt'
Assert-KitchenDsc "the File resource created $TargetPath" {
    Test-Path -Path $TargetPath -PathType Container
}
Assert-KitchenDsc "the File resource wrote $testFile" { Test-Path -Path $testFile -PathType Leaf }

# The contents come from configuration_data in kitchen.windows.yml, so this is
# also the end-to-end check that ps_hash rendered it into the compiled MOF.
Assert-KitchenDsc 'the configuration_data marker reached the compiled MOF' {
    (Get-Content -Path $testFile -Raw).Trim() -eq $Marker
}

if ($failures.Count -gt 0)
{
    Write-Host ''
    Write-Host "$($failures.Count) check(s) failed:"
    $failures | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host ''
Write-Host 'All kitchen-dsc integration checks passed.'
exit 0
