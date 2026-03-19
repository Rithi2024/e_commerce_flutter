[CmdletBinding()]
param(
  [string]$Token,
  [string]$ProjectRef,
  [ValidateRange(6, 10)]
  [int]$OtpLength = 6
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Resolve-Path (Join-Path $scriptDir '..')
$envFile = Join-Path $rootDir '.env'

function Get-DotEnvValues {
  param([string]$Path)

  $values = @{}
  if (-not (Test-Path $Path)) {
    return $values
  }

  foreach ($line in Get-Content $Path) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
      continue
    }

    $separatorIndex = $trimmed.IndexOf('=')
    if ($separatorIndex -lt 1) {
      continue
    }

    $key = $trimmed.Substring(0, $separatorIndex).Trim()
    $value = $trimmed.Substring($separatorIndex + 1)
    if (
      ($value.StartsWith('"') -and $value.EndsWith('"')) -or
      ($value.StartsWith("'") -and $value.EndsWith("'"))
    ) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    $values[$key] = $value
  }

  return $values
}

function Get-ConfigValue {
  param(
    [string]$Name,
    [hashtable]$DotEnvValues
  )

  $envValue = [Environment]::GetEnvironmentVariable($Name)
  if (-not [string]::IsNullOrWhiteSpace($envValue)) {
    return $envValue.Trim()
  }

  if ($DotEnvValues.ContainsKey($Name)) {
    return "$($DotEnvValues[$Name])".Trim()
  }

  return ''
}

function Resolve-ProjectRef {
  param(
    [string]$ExplicitProjectRef,
    [hashtable]$DotEnvValues
  )

  if (-not [string]::IsNullOrWhiteSpace($ExplicitProjectRef)) {
    return $ExplicitProjectRef.Trim()
  }

  $fromEnv = Get-ConfigValue -Name 'SUPABASE_PROJECT_REF' -DotEnvValues $DotEnvValues
  if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
    return $fromEnv
  }

  $supabaseUrl = Get-ConfigValue -Name 'SUPABASE_URL' -DotEnvValues $DotEnvValues
  if ([string]::IsNullOrWhiteSpace($supabaseUrl)) {
    return ''
  }

  try {
    $uri = [Uri]$supabaseUrl
    $host = $uri.Host.Trim()
    if ($host -match '^([^.]+)\.supabase\.co$') {
      return $Matches[1]
    }
  } catch {
    return ''
  }

  return ''
}

$dotEnvValues = Get-DotEnvValues -Path $envFile
$resolvedToken = if ([string]::IsNullOrWhiteSpace($Token)) {
  [Environment]::GetEnvironmentVariable('SUPABASE_ACCESS_TOKEN')
} else {
  $Token.Trim()
}

if ([string]::IsNullOrWhiteSpace($resolvedToken)) {
  throw 'A Supabase personal access token is required. Pass -Token or set SUPABASE_ACCESS_TOKEN.'
}

$resolvedProjectRef = Resolve-ProjectRef -ExplicitProjectRef $ProjectRef -DotEnvValues $dotEnvValues
if ([string]::IsNullOrWhiteSpace($resolvedProjectRef)) {
  throw 'Project ref is required. Pass -ProjectRef, set SUPABASE_PROJECT_REF, or provide SUPABASE_URL in .env.'
}

$requestUri = "https://api.supabase.com/v1/projects/$resolvedProjectRef/config/auth"
$headers = @{
  Authorization = "Bearer $resolvedToken"
  apikey        = $resolvedToken
  'Content-Type' = 'application/json'
}
$body = @{
  mailer_otp_length = $OtpLength
} | ConvertTo-Json

Write-Host "Updating email OTP length to $OtpLength for project $resolvedProjectRef..."

Invoke-RestMethod -Method Patch -Uri $requestUri -Headers $headers -Body $body | Out-Null

Write-Host "Supabase Auth email OTP length updated to $OtpLength."
