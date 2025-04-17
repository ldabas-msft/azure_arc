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

# Fix authentication - create a credential object
try {
    $securePassword = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($ClientId, $securePassword)
    
    Connect-AzAccount -ServicePrincipal -TenantId $TenantId -Credential $credential -Subscription $SubscriptionId -ErrorAction Stop
    Write-Host "Successfully authenticated to Azure" -ForegroundColor Green
} catch {
    Write-Error "Failed to authenticate to Azure: $_"
    throw
}

$vmName = "HCIBox-Client"

try {
    $VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -ErrorAction Stop
    $Location = $VM.Location
    Write-Host "VM located in: $Location" -ForegroundColor Green
} catch {
    Write-Error "Failed to get VM details: $_"
    throw
}

Write-Host "Executing Run Command on VM: $vmName" -ForegroundColor Green

# Create a unique log file path for this run
$logFileName = "HCIBox_Diagnostic_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$remoteTempPath = "C:\Windows\Temp\$logFileName"


# Modified script that properly logs to the file
$diagScript = @"
Write-Host "=== STARTING DIAGNOSTIC SCRIPT ==="

# Set up logging to file
Start-Transcript -Path '$remoteTempPath' -Force

try {
    Write-Host "Diagnostic script started at $(Get-Date)"
    Write-Host "Parameters: SubscriptionId=$SubscriptionId, TenantId=$TenantId, ClientId=$ClientId, ClientSecret=[REDACTED], ResourceGroup=$ResourceGroupName, Location=$Location"
    
    # Download the test script
    Write-Host "Downloading test script..."
    `$webClient = New-Object Net.WebClient
    `$scriptUrl = 'https://raw.githubusercontent.com/ldabas-msft/jumpstart-resources/refs/heads/main/Get-Tests-Devops.ps1'
    Write-Host "Downloading from: `$scriptUrl"
    `$scriptContent = `$webClient.DownloadString(`$scriptUrl)
    Write-Host "Script downloaded, saving to temporary file..."
    
    # Save to temporary file
    `$tempScriptPath = "C:\\Windows\\Temp\\Get-Tests-Devops.ps1"
    Set-Content -Path `$tempScriptPath -Value `$scriptContent
    
    # Execute with parameters explicitly specified
    Write-Host "Executing script with parameters..."
    & `$tempScriptPath -SubscriptionId '$SubscriptionId' -TenantId '$TenantId' -ClientId '$ClientId' -ClientSecret '$ClientSecret' -ResourceGroup '$ResourceGroupName' -Location '$Location'
    
    if (`$?) {
        Write-Host "Script execution completed successfully"
    } else {
        Write-Host "Script execution failed with exit code `$LASTEXITCODE"
    }
}
catch {
    Write-Host "Error during script execution: `$(`$_.Exception.Message)"
    Write-Host "Error details: `$(`$_)"
}
finally {
    Write-Host "Script execution finished at $(Get-Date)"
    Stop-Transcript
}
"@


# Replace placeholder with actual log path
$diagScript = $diagScript.Replace("'LOGFILE_PATH'", "'$remoteTempPath'")

# Start the main command
try {
    Write-Host "Starting main diagnostic command..." -ForegroundColor Cyan
    # Pass parameters with correct names
    $mainJob = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $diagScript -AsJob

    Write-Host "Main command started with job ID: $($mainJob.Id)" -ForegroundColor Green
    Write-Host "Monitoring log file for output at path: $remoteTempPath" -ForegroundColor Cyan

    # Define script to fetch logs
    $getLogsScript = "if (Test-Path '$remoteTempPath') { Get-Content '$remoteTempPath' }"
    
    # Variables to track log monitoring
    $lastPosition = 0
    $logMonitorStartTime = Get-Date
    $maxWaitTime = New-TimeSpan -Minutes 30
    $checkInterval = 10 # seconds
    $logCheckAttempts = 0
    
    # Monitor logs until main job is complete
    do {
        Start-Sleep -Seconds $checkInterval
        $elapsed = (Get-Date) - $logMonitorStartTime
        $jobStatus = Get-Job -Id $mainJob.Id
        
        # Get log content
        $logsResult = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $getLogsScript
        
        if ($logsResult.Value -and $logsResult.Value[0].Message) {
            $logs = $logsResult.Value[0].Message -split "`n"
            
            # Show only new log entries
            if ($logs.Count -gt $lastPosition) {
                $newLogs = $logs[$lastPosition..($logs.Count-1)]
                foreach ($line in $newLogs) {
                    if ($line.Trim()) {
                        Write-Host $line -ForegroundColor Cyan
                    }
                }
                $lastPosition = $logs.Count
            }
        } else {
            # Use Set-Variable instead of increment operator
            $logCheckAttempts = $logCheckAttempts + 1
            if ($logCheckAttempts % 6 -eq 0) { # Report every ~60 seconds if no logs
                Write-Host "No log entries found yet at $remoteTempPath. Still waiting..." -ForegroundColor Yellow
            }
        }
        
        Write-Host "Status: $($jobStatus.State) [Elapsed: $([math]::Floor($elapsed.TotalMinutes))m $($elapsed.Seconds)s]" -ForegroundColor DarkGray
    } while ($jobStatus.State -eq "Running" -and $elapsed -lt $maxWaitTime)

    # Get the final result
    $result = Receive-Job -Id $mainJob.Id
    Remove-Job -Id $mainJob.Id -Force

    # Display results
    Write-Host "Run Command completed with status: $($jobStatus.State)" -ForegroundColor Green

    if ($jobStatus.State -eq "Completed") {
        Write-Host "Command execution succeeded!" -ForegroundColor Green
        
        # Get and display the full log content one final time
        $finalLogsResult = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $getLogsScript
        if ($finalLogsResult.Value -and $finalLogsResult.Value[0].Message) {
            Write-Host "== Full Execution Log ==" -ForegroundColor Green
            Write-Host $finalLogsResult.Value[0].Message -ForegroundColor White
        }
    } else {
        Write-Host "Command execution failed!" -ForegroundColor Red
        Write-Host "Error details:" -ForegroundColor Yellow
        if ($result.Error) {
            $result.Error
        }
        
        # Try to get any error output from the log file
        $finalLogsResult = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $getLogsScript
        if ($finalLogsResult.Value -and $finalLogsResult.Value[0].Message) {
            Write-Host "== Error Log ==" -ForegroundColor Red
            Write-Host $finalLogsResult.Value[0].Message -ForegroundColor White
        }
        
        throw "VM Run Command did not complete successfully"
    }
} catch {
    Write-Error "Error executing run command: $_"
    throw "VM Run Command failed: $_"
}
