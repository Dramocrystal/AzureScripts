function Ensure-AzModules {
    $requiredModules = @("Az.Accounts", "Az.Resources", "Az.Storage", "Az.Compute")
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            Import-Module $module
        }
    }
}

function Connect-ToAzure ($tenantId) {
    Connect-AzAccount -Tenant $tenantId
}

function Ensure-ResourceGroup ($resourceGroup, $location) {
    $rg = Get-AzResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue
    if (-not $rg) {
        New-AzResourceGroup -Name $resourceGroup -Location $location
    }
}

function Ensure-StorageAccount ($resourceGroup, $storageAccountName, $location) {
    $existingStorage = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName -ErrorAction SilentlyContinue
    if (-not $existingStorage) {
        return New-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName -Location $location -SkuName Standard_LRS -Kind StorageV2 -AllowBlobPublicAccess $true
    } else {
        Set-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName -AllowBlobPublicAccess $true
        return $existingStorage
    }
}

function Ensure-StorageContainer ($ctx, $containerName) {
    $existingContainer = Get-AzStorageContainer -Name $containerName -Context $ctx -ErrorAction SilentlyContinue
    if (-not $existingContainer) {
        New-AzStorageContainer -Name $containerName -Context $ctx -Permission Blob
    }
}

function Upload-ZipToBlob ($localFolderPath, $zipFilePath, $ctx, $containerName, $blobName) {
    if (Test-Path $zipFilePath) {
        Remove-Item $zipFilePath -Force
    }
    Compress-Archive -Path "$localFolderPath\*" -DestinationPath $zipFilePath
    Set-AzStorageBlobContent -File $zipFilePath -Container $containerName -Blob $blobName -Context $ctx -Force
}

function Deploy-VMWithWebsite ($resourceGroup, $location, $vmName, $adminUsername, $adminPassword, $vmSize, $image, $blobUrl) {
    $existingVM = Get-AzVM -Name $vmName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue

    if (-not $existingVM) {
        $cred = New-Object PSCredential ($adminUsername, $adminPassword)
        New-AzVM -ResourceGroupName $resourceGroup -Name $vmName -Location $location -VirtualNetworkName "$vmName-vnet" -SubnetName "$vmName-subnet" -PublicIpAddressName "$vmName-ip" -Image $image -Credential $cred -Size $vmSize -OpenPorts 80,3389
    } else {
        Start-AzVM -Name $vmName -ResourceGroupName $resourceGroup
    }

    $installIIS = @"
Install-WindowsFeature -Name Web-Server -IncludeManagementTools
"@
    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $installIIS

    $deployScript = @"
New-Item -Path 'C:\inetpub\wwwroot\catwebsite' -ItemType Directory -Force
Invoke-WebRequest -Uri '$blobUrl' -OutFile 'C:\website.zip'
Expand-Archive -Path 'C:\website.zip' -DestinationPath 'C:\inetpub\wwwroot\catwebsite' -Force
Remove-Item 'C:\website.zip'
"@
    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $deployScript

    $publicIp = (Get-AzPublicIpAddress -ResourceGroupName $resourceGroup | Where-Object { $_.Name -like "*ip*" }).IpAddress
    Write-Host "Website is live at: http://$publicIp/catwebsite"
}
