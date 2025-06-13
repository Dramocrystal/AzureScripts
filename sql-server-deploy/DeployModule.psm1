function Ensure-AzModules {
    $requiredModules = @("Az.Accounts", "Az.Resources", "Az.Storage", "Az.Compute", "Az.Sql")
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
    # Check if storage account exists
    $existingStorage = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName -ErrorAction SilentlyContinue

    if (-not $existingStorage) {
        Write-Host "Creating storage account: $storageAccountName"
        New-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName `
                             -Location $location -SkuName Standard_LRS -Kind StorageV2 `
                             -AllowBlobPublicAccess $true | Out-Null
    } else {
        Write-Host "Storage account exists: $storageAccountName"
        Set-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName `
                             -AllowBlobPublicAccess $true | Out-Null
    }

    # Always generate the storage context using access key (not Azure AD)
    $keys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -Name $storageAccountName
    $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $keys[0].Value

    Write-Host "Storage context created using access key."
    return ($ctx | Select-Object -First 1) # Ensure scalar, not array
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

function Upload-FileToBlob ($filePath, $ctx, $containerName, $blobName) {
    if (-not (Test-Path $filePath)) {
        throw "File not found at $filePath"
    }
    
    Set-AzStorageBlobContent -File $filePath `
                             -Container $containerName `
                             -Blob $blobName `
                             -Context $ctx `
                             -Force

    Write-Host "Uploaded $blobName to container '$containerName'"
}


function Download-File ($url, $destinationPath) {
    if (-not (Test-Path $destinationPath)) {
        Write-Host "Downloading file from $url..."
        Invoke-WebRequest -Uri $url -OutFile $destinationPath -UseBasicParsing
        Write-Host "File downloaded to $destinationPath"
    } else {
        Write-Host "File already exists at $destinationPath"
    }
}

function Create-SqlServer ($resourceGroup, $location, $serverName, $adminUser, $adminPassword) {
    $existing = Get-AzSqlServer -ResourceGroupName $resourceGroup -ServerName $serverName -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "Creating Azure SQL Server: $serverName..."
        $cred = New-Object -TypeName PSCredential -ArgumentList $adminUser, $adminPassword

        try {
            $server = New-AzSqlServer -ResourceGroupName $resourceGroup `
                                      -ServerName $serverName `
                                      -Location $location `
                                      -SqlAdministratorCredentials $cred

            # Confirm creation
            $server = Get-AzSqlServer -ResourceGroupName $resourceGroup -ServerName $serverName
            Write-Host "SQL Server created: $($server.FullyQualifiedDomainName)"
        } catch {
            Write-Host "Failed to create SQL Server: $_"
            throw
        }
    } else {
        Write-Host "SQL Server $serverName already exists."
    }
}


function Migrate-Data-To-DB(
    $resourceGroup,
    $serverName,
    $databaseName,
    $storageAccountName,
    $containerName,
    $blobName,
    $blobUrl,
    $adminUser,
    $adminPassword
) {
    $keys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -Name $storageAccountName
    $storageKey = $keys[0].Value

    Write-Host "Starting import of $blobName into database $databaseName..."

    $import = New-AzSqlDatabaseImport -ResourceGroupName $resourceGroup `
                                      -ServerName $serverName `
                                      -DatabaseName $databaseName `
                                      -StorageKeyType "StorageAccessKey" `
                                      -StorageKey $storageKey `
                                      -StorageUri $blobUrl `
                                      -AdministratorLogin $adminUser `
                                      -AdministratorLoginPassword $adminPassword `
                                      -Edition "Premium" `
                                      -ServiceObjectiveName "P1" `
                                      -DatabaseMaxSizeBytes 5368709120

    Write-Host "Import started. Monitoring progress..."
    $startTime = Get-Date
    $progressId = 1
    $counter = 0

    do {
        Start-Sleep -Seconds 5
        $counter += 1

        $status = Get-AzSqlDatabaseImportExportStatus `
            -OperationStatusLink $import.OperationStatusLink

        $state = $status.Status

        $elapsed = (Get-Date) - $startTime
        $message = "Status: $state - Elapsed: $([math]::Round($elapsed.TotalSeconds))s"

        Write-Progress -Id $progressId `
                       -Activity "Importing $databaseName" `
                       -Status $message `
                       -PercentComplete (($counter % 20) * 5)  # fake % to animate

    } while ($state -eq "InProgress")

    Write-Progress -Id $progressId -Completed -Activity "Importing $databaseName"

    if ($state -eq "Succeeded") {
        Write-Host "`n Import completed successfully in $([math]::Round($elapsed.TotalSeconds)) seconds."
    } else {
        throw "Import failed: $($status.ErrorMessage)"
    }

    return $import
}


function Get-PublicIp {
    return (Invoke-RestMethod -Uri "https://api.ipify.org").ToString()
}


function Configure-SqlFirewall ($resourceGroup, $serverName, $ruleName, $ipAddress) {
    $existingRules = Get-AzSqlServerFirewallRule -ResourceGroupName $resourceGroup -ServerName $serverName

    $ruleExists = $existingRules | Where-Object {
        $_.FirewallRuleName -eq $ruleName -and $_.StartIpAddress -eq $ipAddress -and $_.EndIpAddress -eq $ipAddress
    }

    if (-not $ruleExists) {
        Write-Host "Creating firewall rule: $ruleName for IP $ipAddress"
        New-AzSqlServerFirewallRule `
            -ResourceGroupName $resourceGroup `
            -ServerName $serverName `
            -FirewallRuleName $ruleName `
            -StartIpAddress $ipAddress `
            -EndIpAddress $ipAddress | Out-Null
    } else {
        Write-Host "Firewall rule '$ruleName' for IP $ipAddress already exists."
    }
}



function Deploy-VM (
    $resourceGroup,
    $location,
    $vmName,
    $adminUsername,
    $adminPassword,
    $vmSize,
    $image
) {
    $existingVM = Get-AzVM -Name $vmName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue

    if (-not $existingVM) {
        $cred = New-Object PSCredential ($adminUsername, $adminPassword)
        New-AzVM -ResourceGroupName $resourceGroup `
                 -Name $vmName `
                 -Location $location `
                 -VirtualNetworkName "$vmName-vnet" `
                 -SubnetName "$vmName-subnet" `
                 -PublicIpAddressName "$vmName-ip" `
                 -Image $image `
                 -Credential $cred `
                 -Size $vmSize `
                 -OpenPorts 80,3389 | Out-Null
    } else {
        Start-AzVM -Name $vmName -ResourceGroupName $resourceGroup | Out-Null
    }

    # Install IIS
    $installIIS = @"
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools
"@

    Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $installIIS | Out-Null

    # Ensure only the IP is returned
    $publicIp = (Get-AzPublicIpAddress -ResourceGroupName $resourceGroup | Where-Object { $_.Name -eq "$vmName-ip" }).IpAddress

    if (-not $publicIp) {
        throw "VM public IP not found or not assigned"
    }

    $publicIpStr = $publicIp.ToString()
    Write-Host "VM Public IP: $publicIpStr"

    return $publicIpStr

}


