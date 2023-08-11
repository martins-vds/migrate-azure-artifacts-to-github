[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    $AdosOrg,
    [Parameter(Mandatory = $false)]
    $AdosProject,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    $AdosFeed,    
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    $AdosUsername,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    $GithubOrg,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    $GithubUsername,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    $GithubRepo,
    [Parameter(Mandatory = $true)]
    [ValidateScript({
            if (-Not ($_ | Test-Path) ) {
                throw "Folder '$_' does not exist. Make sure to create it before running the script."
            }

            if (-Not ($_ | Test-Path -PathType Container) ) {
                throw "The Path '$_' argument must be a directory. File paths are not allowed."
            }
        
            return $true 
        })]
    [System.IO.FileInfo]
    $PackagesPath,    
    [Parameter(Mandatory = $false)]
    [string]
    $AdosToken,
    [Parameter(Mandatory = $false)]
    [string]
    $GithubToken
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. $PSScriptRoot\common-packages.ps1
. $PSScriptRoot\common-ados-artifacts.ps1
. $PSScriptRoot\common-nuget.ps1

function RepositoryExits($org, $repository, $token) {
    $reposApi = "https://api.github.com/repos/$org/$repository"

    try {
        Get -uri $reposApi -token $token | Out-Null

        return $true;
    }
    catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        if ($_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
            return $false;
        }
    }
}

$sourcePat = GetToken -token $AdosToken -envToken $env:ADOS_PAT
$targetPat = GetToken -token $GithubToken -envToken $env:GH_PAT

if (-Not(RepositoryExits -org $GithubOrg -repository $GithubRepo -token $targetPat)) {
    Write-Host "Repository '$GithubRepo' does not exist in Github organization '$GithubOrg'." -ForegroundColor Red
    exit 0
}

if ([string]::IsNullOrEmpty($AdosProject)) {
    $sourceNugetPackages = GetAdosPackages -org $AdosOrg -feed $AdosFeed -type "NuGet" -token $sourcePat
}
else {
    $sourceNugetPackages = GetAdosPackages -org $AdosOrg -project $AdosProject -feed $AdosFeed -type "NuGet" -token $sourcePat
}

if ($sourceNugetPackages.Length -eq 0) {
    Write-Host "No nuget packages found in Azure DevOps organization '$AdosOrg'." -ForegroundColor Yellow
    exit 0
}

if ([string]::IsNullOrEmpty($AdosProject)) {
    $sourceNugetConfig = ConfigureAdosNuget -org $AdosOrg -feed $AdosFeed -username $AdosUsername -path $PackagesPath.FullName -token $sourcePat
}
else {
    $sourceNugetConfig = ConfigureAdosNuget -org $AdosOrg -project $AdosProject -feed $AdosFeed -username $AdosUsername -path $PackagesPath.FullName -token $sourcePat
}

$targetNugetConfig = ConfigureGithubNuget -org $GithubOrg -username $GithubUsername -path $PackagesPath.FullName -token $targetPat

$sourceNugetPackages | ForEach-Object {
    $sourceNugetPackage = $_
    $sourceNugetPackageVersions = $sourceNugetPackage.versions

    $sourceNugetPackageVersions | ForEach-Object {
        $sourceNugetPackageVersion = $_
        
        Write-Host "Migrating package '$($sourceNugetPackage.name).$($sourceNugetPackageVersion.version)'..." -ForegroundColor Cyan

        DownloadNugetPackage -package $sourceNugetPackage.name -version $sourceNugetPackageVersion.version -source "ados" -configPath $sourceNugetConfig -packagesPath $PackagesPath.FullName
        
        UnzipNugetPackage -package $sourceNugetPackage.name -version $sourceNugetPackageVersion.version -packagesPath $PackagesPath.FullName

        $spec = ExtractNugetPackageSpec -package $sourceNugetPackage.name -version $sourceNugetPackageVersion.version -packagesPath $PackagesPath.FullName
        
        UpdateNugetPackageRepositoryName -nuspec $spec -org $GithubOrg -repository $GithubRepo
        UpdateNugetPackageProjectUrl -nuspec $spec -org $GithubOrg -repository $GithubRepo

        RepackNugetPackage -nuspec $spec -package $sourceNugetPackage.name -version $sourceNugetPackageVersion.version -packagesPath $PackagesPath.FullName

        PushNugetPackage  -org $GithubOrg -package $sourceNugetPackage.name -version $sourceNugetPackageVersion.version -source "github" -configPath $targetNugetConfig -packagesPath $PackagesPath.FullName

        DeleteNugetPackage -package $sourceNugetPackage.name -version $sourceNugetPackageVersion.version -packagesPath $PackagesPath.FullName 
    }
}

Cleanup -path $PackagesPath

Write-Host "Done." -ForegroundColor Green