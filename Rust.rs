use std::process::Command;
use regex::Regex;
use std::fs::File;
use std::io::Read;
use std::io;
use std::io::Write;

fn extract_info(stock_vbmeta: &str) -> io::Result<Vec<String>> {
    let output = Command::new("avbtool")
        .arg("info_image")
        .arg("--image")
        .arg(stock_vbmeta)
        .output()?;
    
    let output_str = String::from_utf8_lossy(&output.stdout);
    
    let mut info = Vec::new();
    
    let algorithm_regex = Regex::new(r"Algorithm:\s+(\S+)").unwrap();
    if let Some(captures) = algorithm_regex.captures(&output_str) {
        info.push(format!("Algorithm: {}", &captures[1]));
    }
    
    let partition_regex = Regex::new(r"Partition Name:\s+(\S+)\n\s+Rollback Index Location:\s+(\d+)\n\s+Public key \(sha1\):\s+(\S+)").unwrap();
    for captures in partition_regex.captures_iter(&output_str) {
        info.push(format!("Partition Name: {}, Rollback Index Location: {}, Public key (sha1): {}", &captures[1], &captures[2], &captures[3]));
    }
    
    Ok(info)
}

fn calculate_padding_size(file_path: &str) -> io::Result<u32> {
    let mut file = File::open(file_path)?;
    let mut data = Vec::new();
    file.read_to_end(&mut data)?;
    
    if let Some(index_dhtb) = data.windows(4).position(|window| window == b"DHTB") {
        let section_data = &data[index_dhtb + 4..];
        if section_data.contains(&[0, 80, 0, 0]) {
            return Ok(20480);
        } else if section_data.contains(&[0, 64, 0, 0]) {
            return Ok(16384);
        } else if section_data.contains(&[0, 48, 0, 0]) {
            return Ok(12288);
        } else {
            println!("No recognized padding size pattern found after 'DHTB'");
            return Err(io::Error::new(io::ErrorKind::Other, "Unknown padding size pattern"));
        }
    } else {
        println!("Text-string 'DHTB' not found in the file.");
        return Err(io::Error::new(io::ErrorKind::Other, "Text-string 'DHTB' not found"));
    }
}

fn remove_key(partition_name: &str) {
    let key_path = format!("keys/{}_key.bin", partition_name);
    if let Err(_) = std::fs::remove_file(&key_path) {
        println!("Key for partition '{}' not found.", partition_name);
    } else {
        println!("Key for partition '{}' removed successfully.", partition_name);
    }
}

fn generate_public_key(partition_name: &str) {
    let rsa_pem_file = "rsa_4096.pem";
    if let Ok(_) = std::fs::metadata(rsa_pem_file) {
        if let Err(_) = Command::new("avbtool")
            .arg("extract_public_key")
            .arg("--key")
            .arg(rsa_pem_file)
            .arg("--output")
            .arg(format!("keys/{}_key.bin", partition_name))
            .status() {
                println!("Error: Failed to generate public key for partition '{}'.", partition_name);
            }
    } else {
        println!("Error: RSA PEM file '{}' not found.", rsa_pem_file);
    }
}

fn main() {
    println!("Usage: cargo run");

    let stock_vbmeta = "vbmeta-sign.img";

    if let Ok(stock_vbmeta_info) = extract_info(stock_vbmeta) {
        for info in stock_vbmeta_info {
            println!("{}", info);
        }
    }

    if let Ok(padding_size) = calculate_padding_size(stock_vbmeta) {
        println!("Padding size: {}", padding_size);
    } else {
        println!("Failed to determine padding size.");
    }

    let partition_choices = vec!["partition1", "partition2", "partition3"]; // Replace with actual partition names
    let partition_list = partition_choices.iter().enumerate().map(|(i, partition_name)| format!("{}. {}", i + 1, partition_name)).collect::<Vec<String>>().join(" ");
    println!("\nEnter the number corresponding to the partition name you want to modify or swap public keys for:");
    println!("{}", partition_list);

    let mut valid_input = false;
    while !valid_input {
        let mut input = String::new();
        print!("\nEnter the number: ");
        io::stdout().flush().unwrap();
        io::stdin().read_line(&mut input).unwrap();
        
        if let Ok(partition_index) = input.trim().parse::<usize>() {
            if partition_index > 0 && partition_index <= partition_choices.len() {
                let selected_partition = partition_choices[partition_index - 1];
                remove_key(selected_partition);
                generate_public_key(selected_partition);
                valid_input = true;
            } else {
                println!("Error: Please enter a valid number corresponding to a partition name.");
            }
        } else {
            println!("Error: Please enter a valid number corresponding to a partition name.");
        }
    }
}
