. $PSScriptRoot\common-ados.ps1

function GetAdosPackages {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "OrgFeed")]
        [Parameter(Mandatory = $true, ParameterSetName = "ProjFeed")]
        [ValidateNotNullOrEmpty()]
        [string]
        $org,
        [Parameter(Mandatory = $true, ParameterSetName = "ProjFeed")]
        [ValidateNotNullOrEmpty()]
        [string]
        $project,
        [Parameter(Mandatory = $true, ParameterSetName = "OrgFeed")]
        [Parameter(Mandatory = $true, ParameterSetName = "ProjFeed")]
        [ValidateNotNullOrEmpty()]
        [string]
        $feed,
        [Parameter(Mandatory = $true, ParameterSetName = "OrgFeed")]
        [Parameter(Mandatory = $true, ParameterSetName = "ProjFeed")]
        [ValidateNotNullOrEmpty()]
        [string]
        $type,
        [Parameter(Mandatory = $true, ParameterSetName = "OrgFeed")]
        [Parameter(Mandatory = $true, ParameterSetName = "ProjFeed")]
        [ValidateNotNullOrEmpty()]
        [string]
        $token
    )

    process {
        if ([string]::IsNullOrEmpty($project)) {
            $feedApi = "https://feeds.dev.azure.com/$org/_apis/packaging/Feeds/$feed/packages"
        }
        else {
            $feedApi = "https://feeds.dev.azure.com/$org/$project/_apis/packaging/Feeds/$feed/packages"    
        }

        $top = 10
        $packagesApi = "$($feedApi)?api-version=7.0&protocolType=$type&includeAllVersions=true&`$top=$top&`$skip={0}"

        $allPackages = @()
        $skip = 0

        do {
            Write-Verbose "Calling Azure DevOps API '$($packagesApi -f $skip)'..."
            $packages = Get -uri "$($packagesApi -f $skip)" -headers $(BuildAdosHeaders $token)
            $allPackages += $packages.value
            $skip += $top
            Write-Verbose "Fetched $($packages.count) packages from Azure DevOps feed '$feed' in organization '$org'."
        }while ($packages.count -gt 0)

        Write-Verbose "Fetched $($allPackages.count) packages from Azure DevOps feed '$feed' in organization '$org'."

        return $allPackages
    }
}

function IsPackageInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "OrgFeed")]
        [Parameter(Mandatory = $true, ParameterSetName = "ProjFeed")]
        [ValidateNotNullOrEmpty()]
        [string]
        $org,
        [Parameter(Mandatory = $true, ParameterSetName = "ProjFeed")]
        [ValidateNotNullOrEmpty()]
        [string]
        $project,
        [Parameter(Mandatory = $true, ParameterSetName = "OrgFeed")]
        [Parameter(Mandatory = $true, ParameterSetName = "ProjFeed")]
        [ValidateNotNullOrEmpty()]
        [string]
        $feed,
        [Parameter(Mandatory = $true, ParameterSetName = "OrgFeed")]
        [Parameter(Mandatory = $true, ParameterSetName = "ProjFeed")]
        [ValidateNotNullOrEmpty()]
        [string]
        $packageId,
        [Parameter(Mandatory = $true, ParameterSetName = "OrgFeed")]
        [Parameter(Mandatory = $true, ParameterSetName = "ProjFeed")]
        [ValidateNotNullOrEmpty()]
        [string]
        $packageVersionId,
        [Parameter(Mandatory = $true, ParameterSetName = "OrgFeed")]
        [Parameter(Mandatory = $true, ParameterSetName = "ProjFeed")]
        [ValidateNotNullOrEmpty()]
        [string]
        $token
    )
    process {
        if ([string]::IsNullOrEmpty($project)) {
            $feedApi = "https://feeds.dev.azure.com/$org/_apis/packaging/Feeds/$feed/packages"
        }
        else {
            $feedApi = "https://feeds.dev.azure.com/$org/$project/_apis/packaging/Feeds/$feed/packages"    
        }

        $provenance = Get -uri "$feedApi/$packageId/Versions/$packageVersionId/provenance?api-version=7.0-preview.1" -headers $(BuildAdosHeaders $token)
        return $provenance.provenance.provenanceSource -like "*internal*"
    }
}