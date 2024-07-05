use std::env;
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::collections::{HashMap, HashSet};
use std::mem;
use std::path::Path;
use sha2::{Sha256, Digest};
use std::process::Command;

const AVB_MAGIC_LEN: usize = 4;
const AVB_MAGIC: &[u8; AVB_MAGIC_LEN] = b"AVB0";
const AVB_RELEASE_STRING_SIZE: usize = 48;

#[repr(C, packed(4))]
struct AvbVBMetaImageHeader {
    magic: [u8; AVB_MAGIC_LEN],
    required_libavb_version_major: u32,
    required_libavb_version_minor: u32,
    authentication_data_block_size: u64,
    auxiliary_data_block_size: u64,
    algorithm_type: u32,
    hash_offset: u64,
    hash_size: u64,
    signature_offset: u64,
    signature_size: u64,
    public_key_offset: u64,
    public_key_size: u64,
    public_key_metadata_offset: u64,
    public_key_metadata_size: u64,
    descriptors_offset: u64,
    descriptors_size: u64,
    rollback_index: u64,
    flags: u32,
    rollback_index_location: u32,
    release_string: [u8; AVB_RELEASE_STRING_SIZE],
    reserved: [u8; 80],
}

#[repr(C, packed(4))]
struct AvbChainPartitionDescriptor {
    tag: u64,
    num_bytes_following: u64,
    rollback_index_location: u32,
    partition_name_len: u32,
    public_key_len: u32,
    flags: u32,
    reserved: [u8; 60],
}

fn reverse_uint32(x: u32) -> u32 {
    x.swap_bytes()
}

fn reverse_uint64(x: u64) -> u64 {
    x.swap_bytes()
}

fn print_usage() {
    println!("\nUsage: {} <vbmeta_image> [--swap-keys <partition1> <partition2> ... <all>]", env::args().next().unwrap());
    std::process::exit(1);
}

fn print_error(message: &str) {
    eprintln!("\x1b[1;31mError:\x1b[0m {}", message);
}

fn generate_key(name: &str, algorithm: u32) -> io::Result<()> {
    let rsa_size = if algorithm == 2048 { "2048" } else { "4096" };
    let private_key = format!("rsa{}_{}.pem", rsa_size, name);
    
    Command::new("openssl")
        .args(&["genrsa", "-out", &private_key, rsa_size])
        .output()?;

    Command::new("python")
        .args(&["avbtool", "extract_public_key", "--key", &private_key, "--output", &format!("keys/{}_key.bin", name)])
        .output()?;

    Ok(())
}

fn verify_extracted_keys(partition_names: &[String], vbmeta_pubkey_digests: &HashMap<String, Vec<u8>>) -> io::Result<()> {
    // Check if all public keys were extracted
    let missing_keys: Vec<&String> = partition_names.iter()
        .filter(|name| !Path::new(&format!("keys/{}_key.bin", name)).exists())
        .collect();

    if !missing_keys.is_empty() {
        print_error("Public keys for the following partitions can not be extracted:");
        for name in missing_keys {
            print_error(&format!("- {}", name));
        }
        std::process::exit(1);
    }

    // Verify key hashes
    let mut hash_mismatch = false;
    for name in partition_names {
        let key_path = format!("keys/{}_key.bin", name);
        let mut file = File::open(&key_path)?;
        let mut extracted_key = Vec::new();
        file.read_to_end(&mut extracted_key)?;
        let extracted_pubkey_digest = Sha256::digest(&extracted_key);
        if extracted_pubkey_digest.as_slice() != vbmeta_pubkey_digests[name] {
            print_error(&format!("Public key hash mismatch for partition '{}'", name));
            hash_mismatch = true;
        }
    }

    if hash_mismatch {
        print_error("One or more public key hashes do not match the vbmeta image");
        std::process::exit(1);
    }

    println!("\nAll public keys were successfully extracted and verified.");
    Ok(())
}

fn handle_key_swapping(args: &[String], partition_names: &[String], algorithm: u32) -> io::Result<()> {
    let mut swap_for_partitions: HashSet<String> = HashSet::new();
    let mut swap_keys_mode = false;

    for arg in args.iter().skip(2) {
        if arg == "--swap-keys" {
            swap_keys_mode = true;
        } else if swap_keys_mode {
            swap_for_partitions.insert(arg.to_string());
        }
    }

    if !swap_keys_mode {
        return Ok(());
    }

    if swap_for_partitions.is_empty() {
        print_error("No partitions specified after --swap-keys");
        print_usage();
        std::process::exit(1);
    }

    let swap_all = swap_for_partitions.contains("all");

    let partitions_set: HashSet<&String> = partition_names.iter().collect();
    let mut invalid_partition_found = false;

    for partition in &swap_for_partitions {
        if partition == "all" {
            continue;
        }
        if !partitions_set.contains(partition) {
            print_error(&format!("Specified partition '{}' not found in vbmeta image", partition));
            invalid_partition_found = true;
        }
    }

    if invalid_partition_found {
        std::process::exit(1);
    }

    for name in partition_names {
        if swap_all || swap_for_partitions.contains(name) {
            println!("\nGenerating new key for partition: {}", name);
            generate_key(name, algorithm)?;
        }
    }

    Ok(())
}

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        print_error("No input file provided");
        print_usage();
    }
    
    if args.len() < 3 || args[2] != "--swap-keys" {
        print_error("Invalid or missing arguments");
        print_usage();
    }
    
    let partitions = args.iter().skip(3).collect::<Vec<_>>();
    if partitions.is_empty() {
        print_error("No partitions specified after --swap-keys");
        print_usage();
    }
    
    let meta_path = &args[1];
    let buffer = fs::read(meta_path)?;

    if buffer.len() < mem::size_of::<AvbVBMetaImageHeader>() {
        print_error("The provided file is too small to be a valid vbmeta image");
        std::process::exit(1);
    }

    let vbheader: &AvbVBMetaImageHeader = unsafe { mem::transmute(buffer.as_ptr()) };
    if &vbheader.magic != AVB_MAGIC {
        print_error("Provided file is not a valid vbmeta image");
        std::process::exit(1);
    }

    let keys_dir = Path::new("keys");
    if keys_dir.exists() {
        fs::remove_dir_all(keys_dir)?;
    }
    fs::create_dir(keys_dir)?;

    let mut fo = File::create("sign_vbmeta.sh")?;

    let algorithm_type = reverse_uint32(vbheader.algorithm_type);
    let rsa = 256 * if algorithm_type < 4 { 1 } else { 2 };
    
    if algorithm_type < 1 || algorithm_type > 6 {
        print_error("Unsupported algorithm type");
        std::process::exit(1);
    }
    
    let algorithm = 1024 * 2u32.pow(if algorithm_type < 4 { algorithm_type } else { algorithm_type - 3 });
    writeln!(fo, "python avbtool make_vbmeta_image --key rsa{}_vbmeta.pem --algorithm SHA{}_RSA{} \\", algorithm, rsa, algorithm)?;

    let mut chainheader_offset = mem::size_of::<AvbVBMetaImageHeader>() + reverse_uint64(vbheader.authentication_data_block_size) as usize;
    let mut chainheader: &AvbChainPartitionDescriptor = unsafe { mem::transmute(buffer[chainheader_offset..].as_ptr()) };
    let tag = reverse_uint64(chainheader.tag);
    
    let mut partition_names: Vec<String> = Vec::new();
    let mut vbmeta_pubkey_digests: HashMap<String, Vec<u8>> = HashMap::new();
    
    loop {
        let rollback_index_location = reverse_uint32(chainheader.rollback_index_location);
        let partition_name_len = reverse_uint32(chainheader.partition_name_len) as usize;
        let public_key_len = reverse_uint32(chainheader.public_key_len) as usize;

        let name_start = chainheader_offset + mem::size_of::<AvbChainPartitionDescriptor>();
        let name = String::from_utf8_lossy(&buffer[name_start..name_start + partition_name_len]).to_string();
        let key_path = format!("keys/{}_key.bin", name);
        
        println!("Extracting key for partition: {}", name);
        
        let key_start = name_start + partition_name_len;
        let public_key = buffer[key_start..key_start + public_key_len].to_vec();
        
        let vbmeta_pubkey_digest = Sha256::digest(&public_key);
        vbmeta_pubkey_digests.insert(name.clone(), vbmeta_pubkey_digest.to_vec());
        
        fs::write(&key_path, &public_key)?;
        
        partition_names.push(name.clone());
        
        writeln!(fo, "--chain_partition {}:{}:{} \\", name, rollback_index_location, key_path)?;

        let offset = (mem::size_of::<AvbChainPartitionDescriptor>() + partition_name_len + public_key_len + 7) & !7;
        chainheader_offset += offset;
        chainheader = unsafe { mem::transmute(buffer[chainheader_offset..].as_ptr()) };
        
        if tag != reverse_uint64(chainheader.tag) {
            break;
        }
    }
    
    verify_extracted_keys(&partition_names, &vbmeta_pubkey_digests)?;

    handle_key_swapping(&args, &partition_names, algorithm)?;

    let mut padding = 0x1000;
    if u32::from_le_bytes(buffer[..4].try_into().unwrap()) == 0x42544844 {
        padding = u32::from_le_bytes(buffer[0x30..0x34].try_into().unwrap());
    } else if u32::from_le_bytes(buffer[0xFFE00..0xFFE04].try_into().unwrap()) == 0x42544844 {
        padding = u32::from_le_bytes(buffer[0xFFE30..0xFFE34].try_into().unwrap());
    }

    writeln!(fo, "--padding_size {} \\", padding)?;
    writeln!(fo, "--output vbmeta.img")?;

    Ok(())
    }
