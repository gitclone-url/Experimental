#RequireAdmin ; Run script as administrator for elevated privileges

; Function for dynamic control clicking with retries
DynamicControlClick(windowTitle, controlClass, partialText, buttonIndex := 1, maxRetries := 5) {
    controlID := 0
    retryCount := 0

    While (controlID = 0 && retryCount < maxRetries) {
        controlID := ControlGetHandle(windowTitle, "", "ClassName" . controlClass "Text" . partialText "Instance" . buttonIndex)
        If (controlID = 0) {
            Sleep, 500 ; Wait for 0.5 seconds before retrying
            retryCount += 1
        }
    }

    If (controlID <> 0) {
        ControlClick, % "ahk_id " . controlID
    } Else {
        LogError("Control not found after multiple attempts.")
        HandleError("Control not found after multiple attempts.")
    }
}

; Function to handle errors gracefully and provide informative messages
HandleError(errorMessage) {
    MsgBox, 16, Error, % errorMessage
    ExitApp
}

; Function to log errors
LogError(errorMsg) {
    FileAppend, % "Error: " . errorMsg . "`n", error.log
}

; Function to find a device by its name, allowing for partial matches
FindDevice(deviceName, devices) {
    Loop, % devices.MaxIndex()
    {
        If (InStr(devices[A_Index][1], deviceName)) {
            Return devices[A_Index][1]
        }
    }
    Return "" ; Device not found
}

; Function to update device driver
UpdateDeviceDriver(deviceName, driverPath) {
    ; Open Device Manager
    Run, devmgmt.msc
    WinWaitActive, Device Manager

    ; Search for the device
    DynamicControlClick("Device Manager", "Edit1", "^f")
    SendInput, %deviceName%{Enter}
    Sleep, 500 ; Adjust timing as needed

    ; Right-click on the found device and update driver
    DynamicControlClick("Search results", "SysListView32", deviceName, 1)
    SendInput, {U}
    Sleep, 500 ; Adjust timing as needed

    ; Choose "Update driver"
    DynamicControlClick("Context", "MenuItem", "Update driver")
    Sleep, 500 ; Adjust timing as needed

    ; Choose "Browse my computer for drivers"
    DynamicControlClick("Update Driver Software", "Button", "Browse my computer for driver software")
    Sleep, 500 ; Adjust timing as needed

    ; Choose "Let me pick from a list of available drivers"
    DynamicControlClick("Update Driver Software", "Button", "Let me pick from a list of device drivers on my computer")
    Sleep, 500 ; Adjust timing as needed

    ; Click "Have Disk"
    DynamicControlClick("Update Driver Software", "Button", "Have Disk")
    Sleep, 500 ; Adjust timing as needed

    ; Browse to the location of the driver file
    WinActivate, Install From Disk
    ControlSend, Edit1, %driverPath%
    Sleep, 500 ; Adjust timing as needed
    DynamicControlClick("Install From Disk", "Button", "OK")
    Sleep, 500 ; Adjust timing as needed

    ; Select the driver from the list
    DynamicControlClick("Update Driver Software", "Button", "Next")
    Sleep, 500 ; Adjust timing as needed

    ; Finish the installation
    DynamicControlClick("Update Driver Software", "Button", "Finish")
    Sleep, 500 ; Adjust timing as needed

    ; Close Device Manager
    WinClose, Device Manager
}

; Function to list devices
DeviceList() {
    Local $devices[1][2] ; Initialize an empty array to store device information
    Local $i = 1 ; Counter for array elements

    ; Access Device Manager's treeview control
    Local $hTreeView = ControlGetHandle("Device Manager", "", "[CLASS:SysTreeView32]")

    ; Iterate through all items in the treeview
    Local $hItem = TreeView_GetFirstVisible($hTreeView)
    While $hItem <> 0
        Local $text = TreeView_GetItemText($hTreeView, $hItem)
        Local $info = TreeView_GetItemParam($hTreeView, $hItem) ; Retrieve additional information (optional)

        ; Store device name and information in the array
        $devices[$i][1] = $text
        $devices[$i][2] = $info
        $i += 1

        $hItem = TreeView_GetNextVisible($hTreeView, $hItem)
    WEnd

    $devices[0][1] = $i - 1 ; Set the first element to the number of devices

    Return $devices
}

; Main script logic
RunAs, %A_ScriptFullPath% ; Re-run the script with elevated privileges

; Retrieve the device list
devices := DeviceList()

; Prompt the user for device selection using a GUI
Gui, Add, ListBox, vDeviceList
Loop, % devices.MaxIndex()
{
    Gui, Add, ListBoxItem, % devices[A_Index][1]
}
Gui, Add, Button, Default, Update Driver
Gui, Show

GuiClose:
Gui, Submit ; Submit the GUI values
Gui, Destroy

; Check if a device is selected
If (DeviceList = "" or DeviceList.ListIndex = -1) {
    HandleError("No device selected.")
}

; Retrieve selected device name
selectedDeviceName := DeviceList[DeviceList.ListIndex + 1]

; Prompt the user for the driver path
InputBox, driverPath, Enter Driver Path:
If (driverPath = "") {
    ExitApp ; User canceled
}

; Update the device driver
foundDeviceName := FindDevice(selectedDeviceName, devices)
If (foundDeviceName = "") {
    LogError("Selected device not found.")
    HandleError("Selected device not found.")
}

UpdateDeviceDriver(foundDeviceName, driverPath)

MsgBox, Driver update for '%selectedDeviceName%' completed successfully.
ExitApp
