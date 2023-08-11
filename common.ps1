function GetToken ($token, $envToken) {
    if (![string]::IsNullOrEmpty($token)) {
        return $token
    }
    
    if (![string]::IsNullOrEmpty($envToken)) {
        return $envToken
    }

    throw "Either Ados or Github Token are missing. Either provide it through the '-AdosToken' or '-GithubToken' parameter or create the environment variables 'ADOS_PAT' and 'GH_PAT'"
}

function BuildHeaders ($token) {
    $headers = @{
        Accept                 = "application/vnd.github+json"
        Authorization          = "Bearer $token"
        'X-GitHub-Api-Version' = "2022-11-28"
    }

    return $headers
}

function Get {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'Token')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Header')]
        [string]
        $uri,
        [Parameter(Mandatory = $true, ParameterSetName = 'Token')]
        [string]
        $token,
        [Parameter(Mandatory = $true, ParameterSetName = 'Header')]
        [hashtable]
        $headers
    )
        
    process {
        if($PSCmdlet.ParameterSetName -eq 'Token') {
            return Invoke-RestMethod -Uri $uri -Method Get -Headers $(BuildHeaders -token $token)
        }
        else {
            return Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
        }
    }    
}