use std::env;
use std::fs::{self, File};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::Path;

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        println!("No input file");
        return Ok(());
    }
    
    let meta_path = &args[1];
    let meta_dir = Path::new(meta_path).parent().expect("Failed to get parent directory");

    // Create a folder named 'key' in the parent directory
    let key_dir = meta_dir.join("key");
    fs::create_dir_all(&key_dir)?;

    let mut stream = io::Cursor::new(std::fs::read(meta_path)?);

    // Search for 00 00 10 00 (int = 1048576)
    loop {
        if stream.position() as usize > stream.get_ref().len().saturating_sub(4) {
            break;
        }

        let mut buffer = [0u8; 4];
        stream.read_exact(&mut buffer)?;
        let req_value = i32::from_le_bytes(buffer);

        if req_value == 1048576 {
            // Search for name, take last 30 bytes and remove zero
            stream.seek(SeekFrom::Current(-34))?;
            let mut bytes = vec![0u8; 30];
            stream.read_exact(&mut bytes)?;

            let zero_count = bytes.iter().filter(|&&x| x == 0).count();
            
            if zero_count > 10 {
                let name_bytes: Vec<u8> = bytes.into_iter().filter(|&x| x != 0).collect();
                let name = String::from_utf8_lossy(&name_bytes);

                let mut key_bytes = vec![0u8; 1032];
                stream.read_exact(&mut key_bytes)?;

                // Append the folder name to the key path
                let key_path = key_dir.join(format!("{}_key.bin", name));
                let mut file = File::create(&key_path)?;
                file.write_all(&key_bytes)?;
            } else {
                stream.seek(SeekFrom::Current(4))?;
            }
        } else {
            stream.seek(SeekFrom::Current(-3))?;
        }
    }
    Ok(())
                }
    
