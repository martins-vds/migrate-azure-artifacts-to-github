. $PSScriptRoot\common.ps1

function EncodeToken ($token) {
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("`:$token"))
}

function BuildAdoHeaders ($token) {
    $headers = @{
        Authorization = "Basic $(EncodeToken $token)"
    }

    return $headers
}
