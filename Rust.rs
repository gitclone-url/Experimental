mod Keysextractor;
use Keysextractor::extract_keys;
use std::collections::HashMap;
use std::fs::File;
use std::io::{self, Read, Write};
use std::path::Path;
use std::process::Command;
use std::str;
use std::io::prelude::*;

struct Descriptor {
    partition_name: String,
    rollback_index_location: u32,
    public_key: String,
}

struct VbMeta {
    algorithm: String,
    descriptors: HashMap<String, Descriptor>,
}

impl VbMeta {
    fn new() -> Self {
        VbMeta {
            algorithm: String::new(),
            descriptors: HashMap::new(),
        }
    }

    fn parse(&mut self, input: &str) {
        let lines: Vec<&str> = input.lines().collect();
        for line in lines {
            let parts: Vec<&str> = line.split(":").collect();
            match parts[0] {
                "Algorithm" => self.algorithm = parts[1].trim().to_string(),
                "Chain Partition descriptor" => {
                    let partition_name = lines[lines.iter().position(|&r| r == line).unwrap() + 1].split(":").collect::<Vec<&str>>()[1].trim().to_string();
                    let rollback_index_location = lines[lines.iter().position(|&r| r == line).unwrap() + 2].split(":").collect::<Vec<&str>>()[1].trim().parse().unwrap();
                    let public_key = lines[lines.iter().position(|&r| r == line).unwrap() + 3].split(":").collect::<Vec<&str>>()[1].trim().to_string();
                    self.descriptors.insert(partition_name.clone(), Descriptor {
                        partition_name,
                        rollback_index_location,
                        public_key,
                    });
                },
                _ => (),
            }
        }
    }
}

fn calculate_padding_size(file_path: &str) -> Option<usize> {
    let mut file = File::open(file_path).expect("Failed to open file");
    let mut data = Vec::new();
    file.read_to_end(&mut data).expect("Failed to read file");

    let index_dhtb = data.windows(4).position(|window| window == b"DHTB");

    if let Some(index) = index_dhtb {
        let section_data = &data[index + 4..];

        let padding_size_mapping = [
            (&[0x00, 0x50, 0x00, 0x00][..], 20480),
            (&[0x00, 0x40, 0x00, 0x00][..], 16384),
            (&[0x00, 0x30, 0x00, 0x00][..], 12288),
            // Add more mappings as needed
        ];

        for (pattern, size) in &padding_size_mapping {
            if section_data.windows(4).any(|window| window == *pattern) {
                return Some(*size);
            }
        }

        println!("No recognized padding size pattern found after 'DHTB'");
        None
    } else {
        println!("Text-string 'DHTB' not found in the file.");
        None
    }
}


fn main() {
    let output = Command::new("python")
        .arg("avbtool.py")
        .arg("info_image")
        .arg("--image")
        .arg("vbmeta-sign.img")
        .output()
        .expect("Failed to execute command");

    let output_str = str::from_utf8(&output.stdout).unwrap();

    let mut vbmeta = VbMeta::new();
    vbmeta.parse(output_str);

    let file_path = "vbmeta-sign.img";
    if let Some(padding_size) = calculate_padding_size(file_path) {
        println!("Padding size: {}", padding_size);
    } else {
        println!("Failed to determine padding size.");
    }

    if let Err(e) = extract_keys(file_path) {
        eprintln!("Failed to extract keys: {}", e);
    }
                                                                     }
        
