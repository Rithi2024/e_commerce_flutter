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
$otpScript = Join-Path $scriptDir 'set-supabase-email-otp-length.ps1'

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

if (-not (Test-Path $otpScript)) {
  throw "Missing helper script: $otpScript"
}

$dotEnvValues = Get-DotEnvValues -Path $envFile
$resendApiKey = Get-ConfigValue -Name 'RESEND_API_KEY' -DotEnvValues $dotEnvValues
$fromEmail = Get-ConfigValue -Name 'RESEND_FROM_EMAIL' -DotEnvValues $dotEnvValues
$brandName = Get-ConfigValue -Name 'APP_BRAND_NAME' -DotEnvValues $dotEnvValues

if ([string]::IsNullOrWhiteSpace($resendApiKey) -or [string]::IsNullOrWhiteSpace($fromEmail)) {
  throw 'RESEND_API_KEY and RESEND_FROM_EMAIL are required. Set them in OS env vars or .env.'
}

if ([string]::IsNullOrWhiteSpace($brandName)) {
  $brandName = 'MarketFlow'
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
$resolvedToken = if ([string]::IsNullOrWhiteSpace($Token)) {
  $originalToken
} else {
  $Token.Trim()
}

if (-not [string]::IsNullOrWhiteSpace($resolvedToken)) {
  [Environment]::SetEnvironmentVariable('SUPABASE_ACCESS_TOKEN', $resolvedToken)
}

try {
  Push-Location $rootDir

  Invoke-Supabase -Arguments (@('functions', 'deploy', 'resend-email') + $projectArgs)

  $secretArgs = @(
    'secrets',
    'set',
    "RESEND_API_KEY=$resendApiKey",
    "RESEND_FROM_EMAIL=$fromEmail",
    "APP_BRAND_NAME=$brandName"
  ) + $projectArgs

  Invoke-Supabase -Arguments $secretArgs

  & powershell -ExecutionPolicy Bypass -File $otpScript -Token $resolvedToken -ProjectRef $resolvedProjectRef -OtpLength $OtpLength
  if ($LASTEXITCODE -ne 0) {
    throw 'Failed to update Supabase email OTP length.'
  }
} finally {
  Pop-Location
  [Environment]::SetEnvironmentVariable('SUPABASE_ACCESS_TOKEN', $originalToken)
}
