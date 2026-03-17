[CmdletBinding()]
param(
  [string]$Device = 'chrome'
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Resolve-Path (Join-Path $scriptDir '..')
$envKeysPath = Join-Path $scriptDir 'env-keys.txt'
$envFile = Join-Path $rootDir '.env'
$generatedEnvFile = Join-Path $rootDir '.env.generated.run'
$webIndexPath = Join-Path $rootDir 'web\index.html'
$webIndexBackupPath = Join-Path $rootDir 'web\index.html.codex.bak'
$mapsPlaceholder = 'YOUR_GOOGLE_MAPS_WEB_API_KEY'

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

function Get-EnvValues {
  param(
    [string]$KeysPath,
    [string]$DotEnvPath
  )

  $keys = Get-Content $KeysPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') }

  $values = Get-DotEnvValues -Path $DotEnvPath
  foreach ($key in $keys) {
    $envValue = [Environment]::GetEnvironmentVariable($key)
    if (-not [string]::IsNullOrWhiteSpace($envValue)) {
      $values[$key] = $envValue.Trim()
    }
  }

  return @{
    Keys = $keys
    Values = $values
  }
}

function Write-GeneratedEnvFile {
  param(
    [string]$Path,
    [string[]]$Keys,
    [hashtable]$Values
  )

  $lines = foreach ($key in $Keys) {
    if ($Values.ContainsKey($key)) {
      "$key=$($Values[$key])"
    }
  }

  Set-Content -Path $Path -Value $lines
}

function Assert-RequiredValue {
  param(
    [hashtable]$Values,
    [string]$Key,
    [string]$Placeholder
  )

  $value = if ($Values.ContainsKey($Key)) { "$($Values[$Key])".Trim() } else { '' }
  if ([string]::IsNullOrWhiteSpace($value) -or $value -eq $Placeholder) {
    throw "Missing required value for $Key."
  }
}

function Invoke-Cleanup {
  if (Test-Path $generatedEnvFile) {
    Remove-Item $generatedEnvFile -Force
  }
  if (Test-Path $webIndexBackupPath) {
    Move-Item $webIndexBackupPath $webIndexPath -Force
  }
}

$envData = Get-EnvValues -KeysPath $envKeysPath -DotEnvPath $envFile
$envKeys = [string[]]$envData.Keys
$envValues = [hashtable]$envData.Values

Assert-RequiredValue -Values $envValues -Key 'SUPABASE_URL' -Placeholder 'https://YOUR_PROJECT.supabase.co'
Assert-RequiredValue -Values $envValues -Key 'SUPABASE_ANON_KEY' -Placeholder 'YOUR_ANON_KEY'

Write-GeneratedEnvFile -Path $generatedEnvFile -Keys $envKeys -Values $envValues

Copy-Item $webIndexPath $webIndexBackupPath -Force
$webMapsKey = if ($envValues.ContainsKey('GOOGLE_MAPS_WEB_API_KEY')) {
  "$($envValues['GOOGLE_MAPS_WEB_API_KEY'])".Trim()
} else {
  ''
}
if ($webMapsKey -eq $mapsPlaceholder) {
  $webMapsKey = ''
}
if ([string]::IsNullOrWhiteSpace($webMapsKey)) {
  Write-Warning 'GOOGLE_MAPS_WEB_API_KEY is empty; web map features will stay disabled until it is set.'
}

$webIndexContent = Get-Content $webIndexPath -Raw
if ([string]::IsNullOrWhiteSpace($webMapsKey)) {
  $webIndexContent = [System.Text.RegularExpressions.Regex]::Replace(
    $webIndexContent,
    '(?m)^\s*<script src="https://maps\.googleapis\.com/maps/api/js\?key=YOUR_GOOGLE_MAPS_WEB_API_KEY"></script>\r?\n?',
    ''
  )
} else {
  $webIndexContent = $webIndexContent.Replace($mapsPlaceholder, $webMapsKey)
}
Set-Content -Path $webIndexPath -Value $webIndexContent

try {
  Push-Location $rootDir
  flutter run -d $Device --dart-define-from-file=$generatedEnvFile
} finally {
  Pop-Location
  Invoke-Cleanup
}
