[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
  [string]$ManagementSubscriptionId,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
  [string]$ConnectivitySubscriptionId,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
  [string]$IdentitySubscriptionId,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
  [string]$SecuritySubscriptionId,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$')]
  [string]$DefenderSecurityContact,

  [ValidatePattern('^[a-z0-9]+$')]
  [string]$Location = 'australiaeast',

  [ValidateSet(5, 6)]
  [int]$ScenarioNumber = 5,

  [ValidatePattern('^[A-Za-z0-9._()\-]{0,90}$')]
  [string]$ParentManagementGroupId = '',

  [string]$TargetFolderPath = (Join-Path $PSScriptRoot 'work'),

  [switch]$InstallOrUpdateAlzModule,

  [switch]$EnablePaidDefenderPlans
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-FileReplacement {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$OldValue,
    [Parameter(Mandatory = $true)][string]$NewValue
  )

  $content = Get-Content -LiteralPath $Path -Raw
  if (-not $content.Contains($OldValue)) {
    throw "Expected placeholder '$OldValue' was not found in $Path. The official template may have changed."
  }

  $updated = $content.Replace($OldValue, $NewValue)
  [System.IO.File]::WriteAllText($Path, $updated, [System.Text.UTF8Encoding]::new($false))
}

if ($PSVersionTable.PSVersion -lt [version]'7.4.0') {
  throw 'PowerShell 7.4 or newer is required by the current ALZ Accelerator.'
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  throw 'Azure CLI is required and must be available from this PowerShell session.'
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw 'Git is required and must be available from this PowerShell session.'
}

if (Test-Path -LiteralPath $TargetFolderPath) {
  throw "Target folder already exists: $TargetFolderPath. Choose a new folder or move the existing one; this script never overwrites it."
}

$platformSubscriptionIds = @(
  $ManagementSubscriptionId,
  $ConnectivitySubscriptionId,
  $IdentitySubscriptionId,
  $SecuritySubscriptionId
)
if (($platformSubscriptionIds | Select-Object -Unique).Count -ne 4) {
  throw 'Management, Connectivity, Identity, and Security must use four distinct subscription IDs.'
}

$installedModule = Get-InstalledPSResource -Name ALZ -ErrorAction SilentlyContinue
if ($InstallOrUpdateAlzModule) {
  if ($null -eq $installedModule) {
    Install-PSResource -Name ALZ
  }
  else {
    Update-PSResource -Name ALZ
  }
}
elseif ($null -eq $installedModule) {
  throw 'The ALZ module is not installed. Re-run with -InstallOrUpdateAlzModule after reviewing the module source and requirements.'
}

Import-Module ALZ -Force
Test-AcceleratorRequirement

# Scenario 5 is management groups, policy, and management resources only.
# Scenario 6 is single-region Hub-Spoke with Azure Firewall and has a much
# larger cost footprint. This command only creates local configuration files.
New-AcceleratorFolderStructure `
  -iacType 'terraform' `
  -versionControl 'local' `
  -scenarioNumber $ScenarioNumber `
  -targetFolderPath $TargetFolderPath

$configDirectory = Join-Path $TargetFolderPath 'config'
$inputsPath = Join-Path $configDirectory 'inputs.yaml'
$platformPath = Join-Path $configDirectory 'platform-landing-zone.tfvars'

Set-FileReplacement -Path $inputsPath -OldValue '"<region-1>"' -NewValue "`"$Location`""
Set-FileReplacement -Path $inputsPath -OldValue '"<management-subscription-id>"' -NewValue "`"$ManagementSubscriptionId`""
Set-FileReplacement -Path $inputsPath -OldValue '"<connectivity-subscription-id>"' -NewValue "`"$ConnectivitySubscriptionId`""
Set-FileReplacement -Path $inputsPath -OldValue '"<identity-subscription-id>"' -NewValue "`"$IdentitySubscriptionId`""
Set-FileReplacement -Path $inputsPath -OldValue '"<security-subscription-id>"' -NewValue "`"$SecuritySubscriptionId`""
Set-FileReplacement -Path $inputsPath -OldValue 'bootstrap_subscription_id: ""' -NewValue "bootstrap_subscription_id: `"$ManagementSubscriptionId`""

if (-not [string]::IsNullOrWhiteSpace($ParentManagementGroupId)) {
  Set-FileReplacement -Path $inputsPath -OldValue 'root_parent_management_group_id: ""' -NewValue "root_parent_management_group_id: `"$ParentManagementGroupId`""
}

Set-FileReplacement -Path $platformPath -OldValue '<region-1>' -NewValue $Location
Set-FileReplacement -Path $platformPath -OldValue 'replace_me@replace_me.com' -NewValue $DefenderSecurityContact

if (-not $EnablePaidDefenderPlans) {
  $defenderKeys = @(
    'enableAscForServers',
    'enableAscForServersVulnerabilityAssessments',
    'enableAscForSql',
    'enableAscForAppServices',
    'enableAscForStorage',
    'enableAscForContainers',
    'enableAscForKeyVault',
    'enableAscForSqlOnVm',
    'enableAscForArm',
    'enableAscForOssDb',
    'enableAscForCosmosDbs',
    'enableAscForCspm'
  )

  $platformContent = Get-Content -LiteralPath $platformPath -Raw
  foreach ($key in $defenderKeys) {
    $pattern = '(?m)^(\s*' + [regex]::Escape($key) + '\s*=\s*)"DeployIfNotExists"'
    if (-not [regex]::IsMatch($platformContent, $pattern)) {
      throw "Expected Defender setting '$key' was not found. Review the current Accelerator option guidance before deployment."
    }
    $platformContent = [regex]::Replace($platformContent, $pattern, '$1"Disabled"')
  }
  [System.IO.File]::WriteAllText($platformPath, $platformContent, [System.Text.UTF8Encoding]::new($false))
}

$remainingPlaceholders = Select-String -Path $inputsPath, $platformPath -Pattern '<[^>]+>|replace_me@replace_me.com'
if ($remainingPlaceholders) {
  $details = ($remainingPlaceholders | ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }) -join [Environment]::NewLine
  throw "Unresolved Accelerator placeholders remain:`n$details"
}

$moduleVersion = (Get-InstalledPSResource -Name ALZ).Version.ToString()
$metadata = [ordered]@{
  prepared_at_utc        = [DateTime]::UtcNow.ToString('o')
  alz_module_version     = $moduleVersion
  scenario_number        = $ScenarioNumber
  location               = $Location
  defender_plans_enabled = [bool]$EnablePaidDefenderPlans
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $TargetFolderPath 'lab-metadata.json') -Encoding utf8NoBOM

Write-Host ''
Write-Host "Accelerator configuration prepared at: $TargetFolderPath"
Write-Host "ALZ PowerShell module version: $moduleVersion"
Write-Host 'No Azure or version-control resources were created.'
if ($ScenarioNumber -eq 6) {
  Write-Warning 'Scenario 6 includes continuously billed network services. Review every generated setting and current Azure pricing before deployment.'
}
if (-not $EnablePaidDefenderPlans) {
  Write-Host 'Microsoft Defender plan policy parameters were set to Disabled for this cost-controlled exercise.'
}
Write-Host "Next: pwsh ./accelerator/deploy-accelerator.ps1 -WorkspacePath '$TargetFolderPath'"
