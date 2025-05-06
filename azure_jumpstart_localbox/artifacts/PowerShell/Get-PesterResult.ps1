param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName
)

Write-Host "Getting Pester test-result files from storage accounts in resource group $ResourceGroupName" -ForegroundColor Cyan

# Primary download location (keep this as is)
$path = "$env:USERPROFILE\testresults"
$null = New-Item -ItemType Directory -Force -Path $path

# Create pipeline directory for test results if we're in a pipeline
$pipelinePath = $null
if ($env:SYSTEM_DEFAULTWORKINGDIRECTORY) {
    $pipelinePath = Join-Path $env:SYSTEM_DEFAULTWORKINGDIRECTORY "testresults"
    $null = New-Item -ItemType Directory -Force -Path $pipelinePath
    Write-Host "Also copying test results to pipeline path: $pipelinePath" -ForegroundColor Cyan
}

# First verify the resource group exists
try {
    $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
    Write-Host "Resource group $ResourceGroupName found" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Resource group '$ResourceGroupName' could not be found. Please check the name and try again." -ForegroundColor Red
    Write-Host "Available resource groups:" -ForegroundColor Yellow
    Get-AzResourceGroup | Select-Object ResourceGroupName, Location | Format-Table
    return
}

# Get all storage accounts in the resource group
try {
    $StorageAccounts = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    Write-Host "Found $($StorageAccounts.Count) storage account(s) in resource group $ResourceGroupName" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Could not retrieve storage accounts from resource group $ResourceGroupName" -ForegroundColor Red
    Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
    return
}

if ($StorageAccounts.Count -eq 0) {
    Write-Host "No storage accounts found in resource group $ResourceGroupName" -ForegroundColor Yellow
    return
}

$totalFilesDownloaded = 0
$successfulAccount = $null

foreach ($StorageAccount in $StorageAccounts) {
    Write-Host "`nTrying storage account: $($StorageAccount.StorageAccountName)" -ForegroundColor Cyan
    
    # Use storage account key
    try {
        # Get storage account keys with proper error handling
        $ErrorActionPreference = 'SilentlyContinue'
        $error.Clear()
        $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccount.StorageAccountName -ErrorAction SilentlyContinue)[0].Value
        $ErrorActionPreference = 'Continue'
        
        if ($error.Count -gt 0) {
            Write-Host "  Could not retrieve keys for storage account $($StorageAccount.StorageAccountName)" -ForegroundColor Yellow
            Write-Host "  Trying next storage account..." -ForegroundColor Yellow
            continue
        }
        
        $ctx = New-AzStorageContext -StorageAccountName $StorageAccount.StorageAccountName -StorageAccountKey $storageAccountKey
        
        # Try to get blobs from this storage account
        try {
            # Use SilentlyContinue to avoid terminating errors
            $ErrorActionPreference = 'SilentlyContinue'
            $error.Clear()
            $blobs = Get-AzStorageBlob -Container "testresults" -Context $ctx
            $ErrorActionPreference = 'Continue'
            
            if ($error.Count -gt 0) {
                if ($error[0].Exception.Message -like "*AuthorizationFailure*") {
                    Write-Host "  Authorization failure accessing container 'testresults' in $($StorageAccount.StorageAccountName)" -ForegroundColor Yellow
                } else {
                    Write-Host "  Could not access 'testresults' container in storage account $($StorageAccount.StorageAccountName)" -ForegroundColor Yellow
                }
                Write-Host "  Trying next storage account..." -ForegroundColor Yellow
                continue
            }
            
            Write-Host "  Found $($blobs.Count) test result files in storage account $($StorageAccount.StorageAccountName)" -ForegroundColor Green
            
            if ($blobs.Count -eq 0) {
                Write-Host "  No test result files found in this storage account, trying next one..." -ForegroundColor Yellow
                continue
            }
            
            $filesDownloaded = 0
            
            foreach ($blob in $blobs) {
                $destinationblobname = ($blob.Name).Split("/")[-1]
                $destinationpath = "$path/$($destinationblobname)"
            
                try {
                    # Use SilentlyContinue for downloading as well
                    $ErrorActionPreference = 'SilentlyContinue'
                    $error.Clear()
                    Get-AzStorageBlobContent -Container "testresults" -Blob $blob.Name -Destination $destinationpath -Context $ctx -Force | Out-Null
                    $ErrorActionPreference = 'Continue'
                    
                    if ($error.Count -gt 0) {
                        Write-Host "    Failed to download $($blob.Name): $($error[0].Exception.Message)" -ForegroundColor Yellow
                    } else {
                        Write-Host "    Downloaded $($blob.Name) to $destinationpath" -ForegroundColor Green
                        
                        # If we're in a pipeline, also copy to the pipeline path
                        if ($pipelinePath) {
                            $pipelineFilePath = Join-Path $pipelinePath $destinationblobname
                            Copy-Item -Path $destinationpath -Destination $pipelineFilePath -Force
                            Write-Host "    Also copied to $pipelineFilePath" -ForegroundColor Green
                        }
                        
                        $filesDownloaded++
                    }
                }
                catch {
                    Write-Host "    Failed to download $($blob.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            
            Write-Host "  Downloaded $filesDownloaded files from storage account $($StorageAccount.StorageAccountName)" -ForegroundColor Cyan
            $totalFilesDownloaded += $filesDownloaded
            $successfulAccount = $StorageAccount.StorageAccountName
            
            # If we found and downloaded files, we can stop trying other accounts
            if ($filesDownloaded -gt 0) {
                Write-Host "  Successfully downloaded files from storage account $($StorageAccount.StorageAccountName), stopping search" -ForegroundColor Green
                break
            }
        }
        catch {
            # This shouldn't happen with SilentlyContinue, but just in case
            Write-Host "  Unexpected error with storage account $($StorageAccount.StorageAccountName): $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  Trying next storage account..." -ForegroundColor Yellow
        }
    }
    catch {
        # This shouldn't happen with SilentlyContinue, but just in case
        Write-Host "  Unexpected error with storage account $($StorageAccount.StorageAccountName): $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  Trying next storage account..." -ForegroundColor Yellow
    }
}

# Provide a summary
if ($totalFilesDownloaded -gt 0) {
    Write-Host "`n✅ SUCCESS: Downloaded a total of $totalFilesDownloaded test result file(s) from storage account $successfulAccount" -ForegroundColor Green
    Write-Host "All test results downloaded to $path" -ForegroundColor Green
    
    # List the downloaded files
    Write-Host "`nDownloaded Files:" -ForegroundColor Cyan
    Get-ChildItem $path -File | Select-Object Name, Length, LastWriteTime | Format-Table
    
    # If we're in a pipeline, also show the pipeline path files
    if ($pipelinePath) {
        Write-Host "`nFiles also copied to pipeline path ($pipelinePath):" -ForegroundColor Cyan
        Get-ChildItem $pipelinePath -File | Select-Object Name, Length, LastWriteTime | Format-Table
    }
}
else {
    Write-Host "`n❌ ERROR: Could not find or access test result files in any storage account in resource group $ResourceGroupName" -ForegroundColor Red
    Write-Host "Please verify:" -ForegroundColor Yellow
    Write-Host "  1. The 'testresults' container exists in one of the storage accounts" -ForegroundColor Yellow
    Write-Host "  2. You have appropriate permissions to access the storage accounts" -ForegroundColor Yellow
    Write-Host "  3. The test results have been uploaded by the test script" -ForegroundColor Yellow
}
