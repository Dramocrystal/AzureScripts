# Variables
$resourceGroup = "rg-yazid-stage"
$location = "canadaeast"
$vmName = "yazid-vm-web"
$adminUsername = "azureuser"
$adminPassword = ConvertTo-SecureString "b2i2025!" -AsPlainText -Force
$vmSize = "Standard_B2s"
$image = "Win2019Datacenter"
$blobUrl = "https://$($storageAccountName).blob.core.windows.net/$containerName/website.zip"

# Create resource group if needed
if (-not (Get-AzResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $resourceGroup -Location $location
}

# Check if VM exists
$existingVM = Get-AzVM -Name $vmName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue

if (-not $existingVM) {
    Write-Host "Creating VM..."

    $cred = New-Object PSCredential ($adminUsername, $adminPassword)

    New-AzVM `
        -ResourceGroupName $resourceGroup `
        -Name $vmName `
        -Location $location `
        -VirtualNetworkName "$vmName-vnet" `
        -SubnetName "$vmName-subnet" `
        -PublicIpAddressName "$vmName-ip" `
        -Image $image `
        -Credential $cred `
        -Size $vmSize `
        -OpenPorts 80,3389

} else {
    Write-Host "VM already exists. Skipping creation."
    Start-AzVM -Name $vmName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
}


$installIIS = @"
Install-WindowsFeature -Name Web-Server -IncludeManagementTools
"@

Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName `
    -CommandId 'RunPowerShellScript' `
    -ScriptString $installIIS


# Deploy website
$deployScript = @"
Invoke-WebRequest -Uri '$blobUrl' -OutFile 'C:\website.zip'
Expand-Archive -Path 'C:\website.zip' -DestinationPath 'C:\inetpub\wwwroot' -Force
Remove-Item 'C:\website.zip'
"@

Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName `
    -CommandId 'RunPowerShellScript' `
    -ScriptString $deployScript

# Print public IP
$publicIp = (Get-AzPublicIpAddress -ResourceGroupName $resourceGroup | Where-Object { $_.Name -like "*ip*" }).IpAddress
Write-Host "`n Website is live at: http://$publicIp"
