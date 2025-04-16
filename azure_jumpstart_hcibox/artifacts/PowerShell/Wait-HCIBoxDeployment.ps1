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

# Ensure we're authenticated before starting
$spnpassword = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
$spncredential = New-Object System.Management.Automation.PSCredential ($ClientId, $spnpassword)
try {
    Connect-AzAccount -ServicePrincipal -Credential $spncredential -Tenant $TenantId -Subscription $SubscriptionId -ErrorAction Stop
    Write-Host "Successfully authenticated to Azure" -ForegroundColor Green
} catch {
    Write-Error "Failed to authenticate to Azure: $_"
    throw
}

$Location = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name "HCIBox-Client" -ErrorAction Stop).Location
Write-Host "VM located in: $Location" -ForegroundColor Green

# Make sure to use the correct VM name consistently
$vmName = "HCIBox-Client"
$runCommandName = "RunTestsDevops"

# Replace with the actual URL where your script is hosted
$scriptUrl = "https://raw.githubusercontent.com/ldabas-msft/jumpstart-resources/refs/heads/main/Get-Tests-Devops.ps1"

Write-Host "Executing Run Command on VM: $vmName" -ForegroundColor Green
$runCommand = Set-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName -RunCommandName $runCommandName -Location $Location -SourceScriptUri $scriptUrl -Parameter @{
    SubscriptionId = $SubscriptionId
    TenantId = $TenantId
    ClientId = $ClientId
    ClientSecret = $ClientSecret
    ResourceGroup = $ResourceGroupName
    Location = $Location
} -AsyncExecution

Write-Host "Run Command initiated with ID: $($runCommand.Name)" -ForegroundColor Green

# Poll with timeout - will wait up to 60 minutes (3600 seconds)
$timeout = 18000
$elapsed = 0
$pollInterval = 60

do {
    # Reconnect to ensure fresh credentials
    if ($elapsed % 600 -eq 0 -and $elapsed -gt 0) { # Refresh credentials every 10 minutes
        Write-Host "Refreshing Azure credentials..." -ForegroundColor Yellow
        Connect-AzAccount -ServicePrincipal -Credential $spncredential -Tenant $TenantId -Subscription $SubscriptionId -ErrorAction Stop
    }
    
    $job = Get-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName -RunCommandName $runCommandName -Expand InstanceView -ErrorAction Stop
    
    Write-Host "Run Command Status: $($job.InstanceView.ExecutionState) [Elapsed: $elapsed seconds]" -ForegroundColor Cyan
    
    if ($job.InstanceView.ExecutionState -ne "Running") {
        break
    }
    
    Start-Sleep -Seconds $pollInterval
    $elapsed += $pollInterval
    
    if ($elapsed -ge $timeout) {
        Write-Warning "Timeout reached waiting for Run Command to complete"
        break
    }
} while ($true)

Write-Host "Run Command execution completed with status: $($job.InstanceView.ExecutionState)" -ForegroundColor Green

if ($job.InstanceView.ExecutionState -eq "Succeeded") {
    Write-Host "Run Command succeeded" -ForegroundColor Green
} else {
    Write-Host "Run Command output:" -ForegroundColor Yellow
    $job.InstanceView.Output
    Write-Error "Run Command failed or timed out. Status: $($job.InstanceView.ExecutionState)"
    if ($job.InstanceView.Error) {
        Write-Error "Error details: $($job.InstanceView.Error)"
    }
    throw "VM Run Command did not complete successfully"
}
