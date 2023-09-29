# Define the path to the Google USB driver folder
$googleDriverPath = "C:\Path\To\Your\GoogleUSBDriverFolder"

# Get a list of devices with status errors in the "Other devices" section
$devicesWithErrors = Get-PnpDevice | Where-Object { $_.Status -like '*error*' -and $_.Class -eq 'UnknownDevice' }

# Check if any devices with errors were found
if ($devicesWithErrors.Count -eq 0) {
    Write-Host "No devices with errors found in the 'Other devices' section."
} else {
    # Initialize an array to store error messages
    $errorMessages = @()

    # Iterate through each device with an error and attempt to update its driver
    foreach ($device in $devicesWithErrors) {
        $deviceId = $device.InstanceId
        $deviceName = $device.DeviceName
        
        Write-Host "Updating driver for $deviceName (Instance ID: $deviceId)"
        
        # Specify the path to the Google USB driver INF file in the driver folder
        $driverInfPath = Join-Path -Path $googleDriverPath -ChildPath "android_winusb.inf"
        
        # Try to update the driver using the specified INF file
        try {
            Update-PnpDriver -Path $driverInfPath -InstanceId $deviceId -Confirm:$false -Force -ErrorAction Stop
            Write-Host "Driver updated for $deviceName"
        } catch {
            # Capture the error message and add it to the errorMessages array
            $errorMessage = "Failed to update driver for $deviceName: $_"
            $errorMessages += $errorMessage
            Write-Host $errorMessage
        }
    }

    # Check if any errors occurred and display them
    if ($errorMessages.Count -gt 0) {
        Write-Host "Errors occurred during driver updates:"
        $errorMessages | ForEach-Object { Write-Host $_ }
    }
}
