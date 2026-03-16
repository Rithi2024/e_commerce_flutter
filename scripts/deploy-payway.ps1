[CmdletBinding()]
param(
  [string]$Token,
  [string]$ProjectRef
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

function Invoke-Supabase {
  param([string[]]$Arguments)

  & supabase @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Supabase CLI command failed: supabase $($Arguments -join ' ')"
  }
}

if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) {
  throw 'Supabase CLI was not found in PATH.'
}

$dotEnvValues = Get-DotEnvValues -Path $envFile
$merchantId = Get-ConfigValue -Name 'PAYWAY_MERCHANT_ID' -DotEnvValues $dotEnvValues
$apiKey = Get-ConfigValue -Name 'PAYWAY_API_KEY' -DotEnvValues $dotEnvValues
$baseUrl = Get-ConfigValue -Name 'PAYWAY_BASE_URL' -DotEnvValues $dotEnvValues

if ([string]::IsNullOrWhiteSpace($merchantId) -or [string]::IsNullOrWhiteSpace($apiKey)) {
  throw 'PAYWAY_MERCHANT_ID and PAYWAY_API_KEY are required. Set them in OS env vars or .env.'
}

$resolvedProjectRef = if ([string]::IsNullOrWhiteSpace($ProjectRef)) {
  Get-ConfigValue -Name 'SUPABASE_PROJECT_REF' -DotEnvValues $dotEnvValues
} else {
  $ProjectRef.Trim()
}

$projectArgs = @()
if (-not [string]::IsNullOrWhiteSpace($resolvedProjectRef)) {
  $projectArgs = @('--project-ref', $resolvedProjectRef)
}

$originalToken = [Environment]::GetEnvironmentVariable('SUPABASE_ACCESS_TOKEN')
if (-not [string]::IsNullOrWhiteSpace($Token)) {
  [Environment]::SetEnvironmentVariable('SUPABASE_ACCESS_TOKEN', $Token.Trim())
}

try {
  Push-Location $rootDir

  Invoke-Supabase -Arguments (@('functions', 'deploy', 'payway-qr') + $projectArgs)

  $secretArgs = @(
    'secrets',
    'set',
    "PAYWAY_MERCHANT_ID=$merchantId",
    "PAYWAY_API_KEY=$apiKey"
  )
  if (-not [string]::IsNullOrWhiteSpace($baseUrl)) {
    $secretArgs += "PAYWAY_BASE_URL=$baseUrl"
  }
  $secretArgs += $projectArgs

  Invoke-Supabase -Arguments $secretArgs
} finally {
  Pop-Location
  [Environment]::SetEnvironmentVariable('SUPABASE_ACCESS_TOKEN', $originalToken)
}
