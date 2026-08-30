# DSC configuration applied by the Windows integration job.
#
# It deliberately uses only the built-in File resource so the suite exercises
# kitchen-dsc itself -- LCM setup, sandbox staging, MOF compilation and
# Start-DscConfiguration -- rather than a third-party DSC resource module.
Configuration KitchenDscTest
{
    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node $AllNodes.NodeName
    {
        File TestDirectory
        {
            Ensure          = 'Present'
            Type            = 'Directory'
            DestinationPath = $Node.TargetPath
        }

        File TestFile
        {
            Ensure          = 'Present'
            Type            = 'File'
            DestinationPath = Join-Path -Path $Node.TargetPath -ChildPath 'kitchen-dsc.txt'
            Contents        = $Node.Marker
            DependsOn       = '[File]TestDirectory'
        }
    }
}
