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
    [Parameter(Mandatory = $false)]
    [string]
    $AdosToken,
    [Parameter(Mandatory = $false)]
    [string]
    $GithubToken,
    [switch]
    $InternalOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

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

function InstallNugetCli ([string]$InstallPath) {
    Write-Host "Checking if NuGet is installed..." -ForegroundColor Cyan

    if (Get-Command "nuget.exe" -ErrorAction SilentlyContinue) {
        Write-Host "NuGet.exe already installed." -ForegroundColor Cyan
        return
    }

    try {
        Write-Host "Installing NuGet..." -ForegroundColor Cyan
        Invoke-RestMethod -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile "$InstallPath\nuget.exe"
        $env:Path += ";$InstallPath"
    }
    catch {
        Write-Host "Failed to install NuGet. Error: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

function CreateTempFolder {
    $tempFolder = Join-Path -Path $env:Temp -ChildPath $(New-Guid)
    New-Item -ItemType Directory -Path $tempFolder | Out-Null

    return $tempFolder
}

$sourcePat = GetToken -token $AdosToken -envToken $env:ADOS_PAT
$targetPat = GetToken -token $GithubToken -envToken $env:GH_PAT

if (-Not(RepositoryExits -org $GithubOrg -repository $GithubRepo -token $targetPat)) {
    Write-Host "Repository '$GithubRepo' does not exist in Github organization '$GithubOrg'." -ForegroundColor Red
    exit 0
}

$PackagesPath = CreateTempFolder

InstallNugetCli -InstallPath $PackagesPath

Write-Host "Fetching nuget packages from Azure Artifacts feed '$AdosFeed' in Azure DevOps organization '$AdosOrg'..."

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
        
        try {
            if ($InternalOnly) {
                if ([string]::IsNullOrEmpty($AdosProject)) {
                    $isInternal = IsPackageInternal -org $AdosOrg -feed $AdosFeed -packageId $sourceNugetPackage.id -packageVersionId $sourceNugetPackageVersion.id -token $sourcePat
                }
                else {
                    $isInternal = IsPackageInternal -org $AdosOrg -project $AdosProject -feed $AdosFeed -packageId $sourceNugetPackage.id -packageVersionId $sourceNugetPackageVersion.id -token $sourcePat
                }
    
                if (-Not $isInternal) {
                    Write-Host "Skipping package '$($sourceNugetPackage.name).$($sourceNugetPackageVersion.version)' because it is not internal." -ForegroundColor Yellow
                    return
                }
            }
    
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
        catch {
            Write-Host "Failed to migrate package '$($sourceNugetPackage.name).$($sourceNugetPackageVersion.version)'. Error: $($_.Exception.Message)" -ForegroundColor Red
        } 
    }
}

Cleanup -path $PackagesPath

Write-Host "Done." -ForegroundColor Green