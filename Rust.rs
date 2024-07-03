use std::env;
use std::fs::{self, File};
use std::io::{Read, Write};
use std::collections::HashMap;
use std::mem;
use std::path::Path;
use sha2::{Sha256, Digest};

const AVB_MAGIC_LEN: usize = 4;
const AVB_MAGIC: &[u8; AVB_MAGIC_LEN] = b"AVB0"; // The magic number for AVB vbmeta images
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

fn print_error(message: &str) {
    eprintln!("\x1b[1;31mError:\x1b[0m {}", message);
}

fn main() -> std::io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        print_error("No input file provided");
        println!("\nUsage: {} <vbmeta_image>", args[0]);
        std::process::exit(1);
    }
    
    let meta_path = &args[1];
    let buffer = fs::read(meta_path).map_err(|e| {
        print_error(&format!("Failed to read input file: {}", e));
        e
    })?;

    if buffer.len() < mem::size_of::<AvbVBMetaImageHeader>() {
        print_error("The provided file is too small to be a valid vbmeta image");
        std::process::exit(1);
    }

    // Check the magic number
    let vbheader: &AvbVBMetaImageHeader = unsafe { mem::transmute(buffer.as_ptr()) };
    if &vbheader.magic != AVB_MAGIC {
        print_error("Provided file is not a valid vbmeta image");
        std::process::exit(1);
    }

    // Create or recreate the 'keys' directory
    let keys_dir = Path::new("keys");
    if keys_dir.exists() {
        fs::remove_dir_all(keys_dir).map_err(|e| {
            print_error(&format!("Failed to remove existing 'keys' directory: {}", e));
            e
        })?;
    }
    fs::create_dir(keys_dir).map_err(|e| {
        print_error(&format!("Failed to create 'keys' directory: {}", e));
        e
    })?;

    let mut fo = File::create("sign_vbmeta.sh").map_err(|e| {
        print_error(&format!("Failed to create 'sign_vbmeta.sh': {}", e));
        e
    })?;

    let algorithm_type = reverse_uint32(vbheader.algorithm_type);
    let rsa = 256 * if algorithm_type < 4 { 1 } else { 2 };
    
    if algorithm_type < 1 || algorithm_type > 6 {
        print_error("Unsupported algorithm type");
        std::process::exit(1);
    }
    
    let algorithm = 1024 * 2u32.pow(if algorithm_type < 4 { algorithm_type } else { algorithm_type - 3 });
    writeln!(fo, "python avbtool make_vbmeta_image --key rsa{}_vbmeta.pem --algorithm SHA{}_RSA{} \\", algorithm, rsa, algorithm).map_err(|e| {
        print_error(&format!("Failed to write to 'sign_vbmeta.sh': {}", e));
        e
    })?;

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
        
        fs::write(&key_path, &public_key).map_err(|e| {
            print_error(&format!("Failed to write key file '{}': {}", key_path, e));
            e
        })?;
        
        partition_names.push(name.clone());
        
        writeln!(fo, "--chain_partition {}:{}:{} \\", name, rollback_index_location, key_path).map_err(|e| {
            print_error(&format!("Failed to write to 'sign_vbmeta.sh': {}", e));
            e
        })?;

        let offset = (mem::size_of::<AvbChainPartitionDescriptor>() + partition_name_len + public_key_len + 7) & !7;
        chainheader_offset += offset;
        chainheader = unsafe { mem::transmute(buffer[chainheader_offset..].as_ptr()) };
        
        if tag != reverse_uint64(chainheader.tag) {
            break;
        }
    }
    
    // Check if all public keys were extracted
    let missing_keys: Vec<&String> = partition_names.iter()
        .filter(|name| !Path::new(&format!("keys/{}_key.bin", name)).exists())
        .collect();

    if !missing_keys.is_empty() {
        print_error("Public keys for the following partitions were not extracted:");
        for name in missing_keys {
            print_error(&format!("- {}", name));
        }
        std::process::exit(1);
    }
    
    // Verify key hashes
    let mut hash_mismatch = false;
    for name in &partition_names {
        let key_path = format!("keys/{}_key.bin", name);
        let mut file = File::open(&key_path).map_err(|e| {
            print_error(&format!("Failed to open key file '{}': {}", key_path, e));
            e
        })?;
        let mut extracted_key = Vec::new();
        file.read_to_end(&mut extracted_key).map_err(|e| {
            print_error(&format!("Failed to read key file '{}': {}", key_path, e));
            e
        })?;

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
    
    let mut padding = 0x1000;
    if u32::from_le_bytes(buffer[..4].try_into().unwrap()) == 0x42544844 {
        padding = u32::from_le_bytes(buffer[0x30..0x34].try_into().unwrap());
    } else if u32::from_le_bytes(buffer[0xFFE00..0xFFE04].try_into().unwrap()) == 0x42544844 {
        padding = u32::from_le_bytes(buffer[0xFFE30..0xFFE34].try_into().unwrap());
    }

    writeln!(fo, "--padding_size {} \\", padding).map_err(|e| {
        print_error(&format!("Failed to write to 'sign_vbmeta.sh': {}", e));
        e
    })?;
    writeln!(fo, "--output vbmeta.img").map_err(|e| {
        print_error(&format!("Failed to write to 'sign_vbmeta.sh': {}", e));
        e
    })?;
    
    Ok(())
        }
