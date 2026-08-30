# Trivial module used to prove that repository-style staging copied
# test/fixtures/modules onto the PSModulePath of the system under test.
function Get-KitchenDscExampleMarker
{
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    'staged-by-kitchen-dsc'
}

Export-ModuleMember -Function Get-KitchenDscExampleMarker
