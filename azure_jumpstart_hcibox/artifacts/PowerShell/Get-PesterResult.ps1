param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName
)

Write-Host "Getting Pester test-result files from storage account in resource group $ResourceGroupName"

# Create a directory to store the test results
$path = $ENV:SYSTEM_DEFAULTWORKINGDIRECTORY + "/testresults"
$null = New-Item -ItemType Directory -Force -Path $path

# Get the storage account from the resource group
$StorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName | Select-Object -First 1
Write-Host "Using storage account: $($StorageAccount.StorageAccountName)"

# Create a storage context using the connected account (assumes you're already authenticated)
$ctx = New-AzStorageContext -StorageAccountName $StorageAccount.StorageAccountName -UseConnectedAccount

# Get all blobs from the testresults container
$blobs = Get-AzStorageBlob -Container "testresults" -Context $ctx

Write-Host "Found $($blobs.Count) test result files in the storage container"

# Download each blob to the local directory
foreach ($blob in $blobs) {
    $destinationblobname = ($blob.Name).Split("/")[-1]
    $destinationpath = "$path/$($destinationblobname)"

    Write-Host "Downloading $($blob.Name) to $destinationpath"
    
    try {
        Get-AzStorageBlobContent -Container "testresults" -Blob $blob.Name -Destination $destinationpath -Context $ctx -ErrorAction Stop
        Write-Host "Successfully downloaded $($blob.Name)" -ForegroundColor Green
    }
    catch {
        Write-Error -Message "Failed to download blob $($blob.Name): $_"
    }
}

Write-Host "All test results downloaded to $path" -ForegroundColor Green