#!/usr/bin/env fish

# Function to print error messages and exit
function exit_with_error
    echo
    echo "Error: $argv[1]"
    echo
    echo "Reason: $argv[2]"
    exit 1
end

# Function to pull the boot image for a dual-slot device
function pull_boot_image_dual_slot
    set boot_a_path $argv[1]
    set boot_b_path $argv[2]
    set active_slot (getprop ro.boot.slot_suffix)

    echo
    echo "It is recommended to pull the boot image according to the current active slot, which is ($active_slot)."
    echo

    while true
        read -P "Which boot slot image would you like to pull? (a/b): " -l chosen_slot
        switch $chosen_slot
            case a
                set boot_image_path $boot_a_path
                break
            case b
                set boot_image_path $boot_b_path
                break
            case '*'
                echo "Invalid input. Please choose either 'a' or 'b'."
                continue
        end
    end

    echo "Pulling the boot image from $boot_image_path..."
    if dd if=$boot_image_path of=./boot$active_slot.img
        echo "Boot image successfully pulled and saved in your "(basename $PWD)" directory."
    else
        exit_with_error "Failed to pull the boot image" "dd command failed"
    end
end

# Function to pull the boot image for a single-slot device
function pull_boot_image_single_slot
    set boot_path $argv[1]

    echo
    echo "Pulling the boot image from $boot_path..."
    if dd if=$boot_path of=./boot.img
        echo "Boot image successfully pulled and saved in your "(basename $PWD)" directory."
    else
        exit_with_error "Failed to pull the boot image" "dd command failed"
    end
end

# Main script starts here
if test (whoami) != "root"
    exit_with_error "Insufficient privileges" "Please run this script as root."
end

echo "########################################"
echo "#    Boot Image Puller for Android     #"
echo "#         Developed by Abhijeet        #"
echo "########################################"
echo

# New logic to get boot slots path using a loop
set -l boot_names boot boot_a boot_b
for name in $boot_names
    set path (find /dev/block -type l -name $name -print | head -n 1)
    if test -n "$path"
        echo "$name = $path"
        switch $name
            case boot_a
                set boot_a_path $path
            case boot_b
                set boot_b_path $path
            case '*'
                set boot_path $path
        end
    end
end

# Check if paths were found and call the function to pull the boot image
if test -n "$boot_a_path" -a -n "$boot_b_path"
    echo "Device has dual boot slots."
    pull_boot_image_dual_slot $boot_a_path $boot_b_path
else if test -n "$boot_path"
    echo "Device has a single boot slot."
    pull_boot_image_single_slot $boot_path
else
    exit_with_error "No boot slots found" "Unable to find boot slots."
end
