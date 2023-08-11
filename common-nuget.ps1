function ConfigureGithubNuget ($org, $username, $path, $token) {  
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
    <packageSources>
        <clear />
        <add key="github" value="https://nuget.pkg.github.com/$org/index.json" />
        <add key="nuget" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
    </packageSources>
    <packageSourceCredentials>
        <github>
            <add key="Username" value="$username" />
            <add key="ClearTextPassword" value="$token" />
        </github>
    </packageSourceCredentials>
</configuration>
"@  

    return ConfigureNuget -path $path -configXml $xml
}

function ConfigureAdosNuget ($org, $project, $feed, $username, $path, $token) {
    if (![string]::IsNullOrEmpty($project)) {
        $org = "$org/$project"
    }

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
    <packageSources>
        <clear />
        <add key="ados" value="https://pkgs.dev.azure.com/$org/_packaging/$feed/nuget/v3/index.json" />
        <add key="nuget" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
    </packageSources>
    <packageSourceCredentials>
        <ados>
            <add key="Username" value="$username" />
            <add key="ClearTextPassword" value="$token" />
        </ados>
    </packageSourceCredentials>
</configuration>
"@

    return ConfigureNuget -path $path -configXml $xml
}

function ConfigureNuget ($path, $configXml) {
    $orgConfig = "$path\$($org.Trim())"

    if (-Not(Test-Path -Path $orgConfig)) {
        New-Item -Path $orgConfig -ItemType Directory | Out-Null
    }
    
    $nugetConfig = "$orgConfig\nuget.config"

    If (Test-Path -Path $nugetConfig) {
        Remove-Item -Path $nugetConfig | Out-Null
    }
    
    New-Item -Path $nugetConfig -Value $configXml | Out-Null

    return $orgConfig
}

function DownloadNugetPackage($package, $version, $configPath, $packagesPath, $source) {
    Exec { nuget install $package -Version $version -Source $source -Source nuget -OutputDirectory $packagesPath -ConfigFile $configPath\nuget.config -NonInteractive } | Out-Null

    Move-Item -Path $packagesPath\$($package).$($version)\$($package).$($version).nupkg -Destination $packagesPath -Force | Out-Null
    Remove-Item -Path $packagesPath\$($package).$($version) -Recurse -Force | Out-Null
}

function UnzipNugetPackage($package, $version, $packagesPath) {
    Expand-Archive -Path $packagesPath\$($package).$($version).nupkg -DestinationPath $packagesPath\$($package).$($version) | Out-Null    
}

function ExtractNugetPackageSpec($package, $version, $packagesPath) {
    return [xml] (Get-Content $packagesPath\$($package).$($version)\$($package).nuspec)
}

function UpdateNugetPackageRepositoryName($nuspec, $org, $repository) {
    if ($nuspec.package.metadata.repository.url) {
        $nuspec.package.metadata.repository.url = "https://github.com/$org/$repository"
    }else{
        $repositoryNode = $nuspec.CreateElement("repository")
        $repositoryNode.SetAttribute("type", "git")
        $repositoryNode.SetAttribute("url", "https://github.com/$org/$repository")

        $nuspec.package.metadata.AppendChild($repositoryNode) | Out-Null
    }    
}

function UpdateNugetPackageProjectUrl($nuspec, $org, $repository) {  
    if ($nuspec.package.metadata.projectUrl) {
        $nuspec.package.metadata.projectUrl = "https://github.com/$org/$repository.git"
    }else{
        $projectUrlNode = $nuspec.CreateElement("projectUrl")
        $projectUrlNode.InnerText = "https://github.com/$org/$repository.git"

        $nuspec.package.metadata.AppendChild($projectUrlNode) | Out-Null
    }
}

function RepackNugetPackage($nuspec, $package, $version, $packagesPath) {
    $nuspec.OuterXml | Set-Content -Path $packagesPath\$($package).$($version)\$($package).nuspec -Force | Out-Null
    Exec { nuget pack $packagesPath\$($package).$($version)\$($package).nuspec -OutputDirectory $packagesPath -NonInteractive } | Out-Null    
}

function PushNugetPackage($org, $package, $version, $configPath, $packagesPath, $source) {
    Exec { nuget push $packagesPath\$($package).$($version).nupkg -Source $source -ConfigFile $configPath\nuget.config -NonInteractive -SkipDuplicate } | Out-Null
}

function DeleteNugetPackage($package, $version, $packagesPath) {
    Remove-Item -Path $packagesPath\$($package).$($version) -Recurse -Force | Out-Null
}