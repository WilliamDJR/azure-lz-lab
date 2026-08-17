[CmdletBinding()]
param(
  [string]$WorkspacePath = (Join-Path $PSScriptRoot 'work'),
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$inputsPath = Join-Path $WorkspacePath 'config/inputs.yaml'
$platformPath = Join-Path $WorkspacePath 'config/platform-landing-zone.tfvars'
$libraryPath = Join-Path $WorkspacePath 'config/lib'
$outputPath = Join-Path $WorkspacePath 'output'

foreach ($path in @($inputsPath, $platformPath, $libraryPath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required Accelerator input was not found: $path"
  }
}

$unresolved = Select-String -Path $inputsPath, $platformPath -Pattern '<[^>]+>|replace_me@replace_me.com'
if ($unresolved) {
  throw 'Configuration still contains unresolved placeholders. Do not deploy it.'
}

Import-Module ALZ -Force
Test-AcceleratorRequirement

$inputsText = Get-Content -LiteralPath $inputsPath -Raw
$bootstrapMatch = [regex]::Match($inputsText, '(?m)^bootstrap_subscription_id:\s*"([0-9a-fA-F-]{36})"')
if (-not $bootstrapMatch.Success) {
  throw 'A concrete bootstrap_subscription_id was not found in inputs.yaml.'
}
$expectedBootstrapSubscription = $bootstrapMatch.Groups[1].Value

Write-Host 'Accelerator bootstrap inputs:'
Write-Host "  Bootstrap: $inputsPath"
Write-Host "  Platform : $platformPath"
Write-Host "  Library  : $libraryPath"
Write-Host "  Output   : $outputPath"
Write-Host ''

if (-not $Execute) {
  Write-Host 'PREVIEW ONLY: Deploy-Accelerator was not invoked.'
  Write-Host 'Review the generated files and official cost/cleanup guidance, then rerun with -Execute.'
  exit 0
}

$currentSubscription = & az account show --query id -o tsv --only-show-errors
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($currentSubscription)) {
  throw 'Azure CLI is not logged in. Run az login and select the bootstrap subscription.'
}
$currentSubscription = $currentSubscription.Trim()
if ($currentSubscription -ne $expectedBootstrapSubscription) {
  throw "Azure CLI targets $currentSubscription, but inputs.yaml expects bootstrap subscription $expectedBootstrapSubscription."
}

$confirmation = Read-Host "Type DEPLOY-ALZ-ACCELERATOR to bootstrap Azure resources in subscription $currentSubscription"
if ($confirmation -ne 'DEPLOY-ALZ-ACCELERATOR') {
  throw 'Deployment cancelled.'
}

$deployParameters = @{
  inputs                 = @($inputsPath, $platformPath)
  starterAdditionalFiles = $libraryPath
  output                 = $outputPath
}

# The ALZ module presents its own Terraform plan and confirmation. This wrapper
# deliberately does not pass an auto-approve option.
Deploy-Accelerator @deployParameters

Write-Host ''
Write-Host 'Bootstrap completed. Review the generated output before running its deploy-local.ps1 script.'
Write-Host 'The Platform landing zone has not necessarily been applied yet; follow Phase 3 of the official guide.'
