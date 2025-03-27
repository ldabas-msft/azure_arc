param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    [Parameter(Mandatory=$true)]
    [string]$ClientId,
    [Parameter(Mandatory=$true)]
    [string]$ClientSecret
)

Write-Host "Starting VM Run Command to run tests on HCIBox-Client in resource group $ResourceGroupName"

$Location = (Get-AzVM -ResourceGroupName $ResourceGroupName).Location

# Make sure to use the correct VM name consistently
$vmName = "HCIBox-Client"
$runCommandName = "RunTestsDevops"

# Replace with the actual URL where your script is hosted
$scriptUrl = "https://raw.githubusercontent.com/yourusername/yourrepo/main/Get-Tests-Devops.ps1"#### UPDATE THIS PATH TO THE PATH OF THE SCRIPT ON GITHUB

Set-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName -RunCommandName $runCommandName -Location $Location -SourceScriptUri $scriptUrl -Parameter @{
    SubscriptionId = $SubscriptionId
    TenantId = $TenantId
    ClientId = $ClientId
    ClientSecret = $ClientSecret
    ResourceGroup = $ResourceGroupName
    Location = $Location
} -AsyncExecution

do {
    $job = Get-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName -RunCommandName $runCommandName -Expand InstanceView

    Write-Host "Instance view of job:" -ForegroundColor Green
    $job.InstanceView
    Start-Sleep -Seconds 60

} while ($job.InstanceView.ExecutionState -eq "Running")

Write-Host "Job completed" -ForegroundColor Green
$job