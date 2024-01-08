use std::fs::File;
use std::io::{self, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

const SEARCH_VALUE: i32 = 1048576;
const NAME_LENGTH: usize = 30;
const KEY_LENGTH: usize = 1032;

fn main() {
    if let Some(meta_path) = std::env::args().nth(1) {
        if let Some(meta_dir) = Path::new(&meta_path).parent() {
            if let Ok(mut stream) = File::open(&meta_path).map(io::BufReader::new) {
                while let Some(key_info) = find_next_key(&mut stream) {
                    if let Ok((name, key)) = key_info {
                        save_key_file(&meta_dir, name, key);
                    }
                }
            } else {
                eprintln!("Failed to open file: {}", meta_path);
            }
        } else {
            eprintln!("Invalid parent directory: {}", meta_path);
        }
    } else {
        eprintln!("No input file provided");
    }
}

fn find_next_key<R: Read + Seek>(stream: &mut R) -> Option<Result<(String, Vec<u8>), io::Error>> {
    loop {
        if stream.seek(SeekFrom::Current(4)).is_err() || stream.seek(SeekFrom::Current(-4)).is_err() {
            break;
        }

        if let Ok(req_value) = stream.read_i32::<std::io::LittleEndian>() {
            if req_value == SEARCH_VALUE {
                if stream.seek(SeekFrom::Current(-(NAME_LENGTH as i64 + 4))).is_err() {
                    break;
                }

                let mut bytes = vec![0; NAME_LENGTH];
                if stream.read_exact(&mut bytes).is_err() {
                    break;
                }

                if bytes.iter().filter(|&&a| a == 0).count() > 10 {
                    if let Ok(mut key_bytes) = read_exact_n_bytes(stream, KEY_LENGTH) {
                        let name = String::from_utf8_lossy(&bytes).trim_end_matches(char::from(0)).to_string();
                        return Some(Ok((name, key_bytes)));
                    }
                } else {
                    stream.seek(SeekFrom::Current(4)).unwrap_or(());
                }
            } else {
                stream.seek(SeekFrom::Current(-3)).unwrap_or(());
            }
        } else {
            break;
        }
    }
    None
}

fn read_exact_n_bytes<R: Read>(reader: &mut R, n: usize) -> Result<Vec<u8>, io::Error> {
    let mut buffer = vec![0; n];
    reader.read_exact(&mut buffer)?;
    Ok(buffer)
}

fn save_key_file(dir: &Path, name: String, key: Vec<u8>) {
    let file_path = dir.join(format!("{}_key.bin", name));
    if let Err(err) = std::fs::write(&file_path, &key) {
        eprintln!("Failed to write key file {}: {}", file_path.display(), err);
    }
}
