#!/usr/bin/env python3

import subprocess
import sys
import time

def print_error(message):
    print("\033[31m{}\033[0m".format(message))

def print_success(message):
    print("\033[32m{}\033[0m".format(message))

def print_info(message):
    print("\033[34m{}\033[0m".format(message))

def main():
    print("      *********************000 of 000******************")
    print("             ____ ___ ____            _       _   ")
    print("            | __ )_ _/ ___|  ___ _ __(_)_ __ | |_ ")
    print("            |  _ \| |\___ \ / __| '__| | '_ \| __|")
    print("            | |_) | | ___) | (__| |  | | |_) | |_ ")
    print("            |____/___|____/ \___|_|  |_| .__/ \__|")
    print("                                       |_|        ")
    time.sleep(0.5)
    print("")
    print("  𝔸 𝕓𝕠𝕠𝕥 𝕚𝕞𝕒𝕘𝕖 𝕤𝕚𝕘𝕟𝕚𝕟𝕘 𝕤𝕔𝕣𝕚𝕡𝕥 𝕗𝕠𝕣 𝕦𝕟𝕚𝕤𝕠𝕔 𝕔𝕙𝕚𝕡𝕤𝕖𝕥 𝕓𝕒𝕤𝕖𝕕 𝕡𝕙𝕠𝕟𝕖𝕤")
    time.sleep(0.5)
    print("")
    print("                      - 𝙼𝚊𝚍𝚎 𝚋𝚢 𝙰𝚋𝚑𝚒𝚓𝚎𝚎𝚝")
    print("      *************************************************")
    print("")
    print("----------------------------")
    try:
        python2_version = subprocess.check_output(["python2", "--version"], stderr=subprocess.STDOUT, text=True).strip()
        print_info("Python 2 is already installed.")
        print_info("Python Version: {}".format(python2_version))
    except subprocess.CalledProcessError:
        print_info("Python 2 is not installed. Installing...")
        try:
            subprocess.check_call(["pkg", "install", "python2", "-y"])
        except subprocess.CalledProcessError:
            print_error("Python 2 installation failed.")
            sys.exit(1)
        print_success("Python 2 installed successfully.")
    print("----------------------------------")
    try:
        openssl_version = subprocess.check_output(["openssl", "version"], stderr=subprocess.STDOUT, text=True).strip()
        print_info("OpenSSL Tool is already installed.")
        print_info("OpenSSL Version: {}".format(openssl_version.split()[1]))
    except subprocess.CalledProcessError:
        print_info("OpenSSL Tool is not installed. Installing...")
        try:
            subprocess.check_call(["pkg", "install", "openssl-tool", "-y"])
        except subprocess.CalledProcessError:
            print_error("OpenSSL Tool installation failed.")
            sys.exit(1)
        print_success("OpenSSL Tool installed successfully.")
    
    print("--------------------------------------")
    print_info("Checking Boot image info, please wait...")
    print("------------------------------------------")
    time.sleep(3)
    print("")
    try:
        output = subprocess.check_output(["python2", "avbtool", "info_image", "--image", "boot.img"], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        print_error("Failed to check 'boot image info!'. Please make sure the 'boot.img' file is placed in the folder.")
        print_error("Error:", e.output)
        sys.exit(1)

    lines = output.splitlines()
    fingerprint = None
    for line in lines:
        if "com.android.build.boot.fingerprint" in line:
            fingerprint = line.split("'")[1]
            break

    if fingerprint is None:
        print_error("Failed to extract fingerprint value.")
        sys.exit(1)

    fingerprint = fingerprint.replace("'", "").replace('"', '').replace('[', '').replace(']', '')

    print_info("Signing in progress, please wait...")
    time.sleep(10)
    
    cmd = [
        "python2", "avbtool", "add_hash_footer", "--image", "boot.img", "--partition_name", "boot",
        "--partition_size", "67108864", "--key", "boot.pem", "--algorithm", "SHA256_RSA4096",
        "--prop", "com.android.build.boot.fingerprint:{}".format(fingerprint),
        "--prop", "com.android.build.boot.os_version:11"
    ]
    try:
         output = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
  except subprocess.CalledProcessError as e:
         error_output = e.output
         if "avbtool:" in error_output:
         print_error("Error:", error_output)
         sys.exit(1)
    else:
        print("")
        print("Done ✅")
        print("___________________________________________________________")

        message = "Boot image signing done! You can now flash the signed boot Image to your phone."
        length = len(message)
        print("-" * length)
        print_success(message)
        print("-" * length)
        sys.exit(0)

if __name__ == "__main__":
    main()