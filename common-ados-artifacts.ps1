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

        $packagesApi = "$($feedApi)?api-version=7.0&protocolType=$type&includeAllVersions=true&`$top=100&`$skip={0}"

        $allPackages = @()
        $skip = 0

        do {
            $packages = Get -uri "$($packagesApi -f $skip)" -headers $(BuildAdosHeaders $token)
            $allPackages += $packages.value
            $skip += 100
        }while ($packages.count -gt 0)

        $internalPackages = @($allPackages | Where-Object { 
                $package = $_
                $package.versions = @($package.versions | Where-Object {
                        $packageVersion = $_
                        $provenance = Get -uri "$feedApi/$($package.id)/Versions/$($packageVersion.id)/provenance?api-version=7.0-preview.1" -headers $(BuildAdoHeaders $token)
                        return $provenance.provenance.provenanceSource -like "*internal*"
                    })

                return $package.versions.count -gt 0
            })

        return $internalPackages
    }
}