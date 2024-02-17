import subprocess
import re
import os
from keyextractor import extract_keys_from_vbmeta

def extract_info(stock_vbmeta):
    command = f"python avbtool info_image --image {stock_vbmeta}"
    output = subprocess.check_output(command, shell=True, text=True)
    
    info = {
        "algorithm": "",
        "public_keys": {},
        "rollback_indices": {},
        "partition_names": []
    }
    
    # Extract algorithm
    algorithm_match = re.search(r"Algorithm:\s+(\S+)", output)
    if algorithm_match:
        info["algorithm"] = algorithm_match.group(1)
    
    # Extract partition information
    partition_matches = re.findall(r"Partition Name:\s+(\S+)\n\s+Rollback Index Location:\s+(\d+)\n\s+Public key \(sha1\):\s+(\S+)", output)
    for partition_name, rollback_index, public_key_hash in partition_matches:
        info["partition_names"].append(partition_name)
        info["rollback_indices"][partition_name] = int(rollback_index)
        info["public_keys"][partition_name] = public_key_hash
    
    return info

def calculate_padding_size(file_path):
    with open(file_path, "rb") as file:
        data = file.read()

    # Find the index of the text-string "DHTB"
    index_dhtb = data.find(b'DHTB')

    if index_dhtb != -1:
        # Extract the section following "DHTB"
        section_data = data[index_dhtb + 4:]

        # Check for specific byte sequences in the extracted section
        if b'\x00\x50\x00\x00' in section_data:
            return 20480
        elif b'\x00\x40\x00\x00' in section_data:
            return 16384
        elif b'\x00\x30\x00\x00' in section_data:
            return 12288
        # Add more byte sequences as needed
        else:
            print("No recognized padding size pattern found after 'DHTB'")
            return None
    else:
        print("Text-string 'DHTB' not found in the file.")
        return None

def remove_key(partition_name):
    key_path = f"keys/{partition_name}_key.bin"
    if os.path.exists(key_path):
        os.remove(key_path)
        print(f"Key for partition '{partition_name}' removed successfully.")
    else:
        print(f"Key for partition '{partition_name}' not found.")

def generate_public_key(partition_name):
    rsa_pem_file = "rsa_4096.pem"
    if os.path.exists(rsa_pem_file):
        command = f"python avbtool extract_public_key --key {rsa_pem_file} --output keys/{partition_name}_key.bin"
        try:
            subprocess.run(command, shell=True, check=True)
        except subprocess.CalledProcessError:
            print(f"Error: Failed to generate public key for partition '{partition_name}'.")
    else:
        print(f"Error: RSA PEM file '{rsa_pem_file}' not found.")

def main():
    print("Usage: python main.py")
    
    stock_vbmeta= "vbmeta-sign.img"  
    stock_vbmeta_info = extract_info(stock_vbmeta)
    
    extract_keys_from_vbmeta(stock_vbmeta, stock_vbmeta_info["public_keys"])
    
    padding_size = calculate_padding_size(stock_vbmeta)
    if padding_size is not None:
        print(f"Padding size: {padding_size}")
    else:
        print("Failed to determine padding size.")
        
    partition_choices = stock_vbmeta_info["partition_names"]
    partition_list = " ".join(f"{i}.{partition_name}" for i, partition_name in enumerate(partition_choices, 1))

    
    valid_input = False
    print("\nEnter the number corresponding to the partition name you want to modify or swap public keys for:")
    print(partition_list)
    
    while not valid_input:
        partition_name_index = input("\nEnter the number: ")

        try:
            partition_index = int(partition_name_index) - 1
            if 0 <= partition_index < len(partition_choices):
                selected_partition = partition_choices[partition_index]
                
                remove_key(selected_partition)
                generate_public_key(selected_partition)
                
                valid_input = True
            else:
                raise ValueError
        except ValueError:
            print("Error: Please enter a valid number corresponding to a partition name.")
        
if __name__ == "__main__":
    main()
    
