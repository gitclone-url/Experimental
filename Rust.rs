use std::env;
use std::fs;
use std::path::Path;
use std::sync::Mutex;
use reqwest::Client;
use reqwest::header::{HeaderMap, ACCEPT_ENCODING, CONTENT_TYPE};
use serde_json::Value;
use url::form_urlencoded;
use xml::EventWriter;
use xml::writer::EmitterConfig;
use xml::writer::EventWriter;
use xml::writer::XmlEvent;

async fn serialize_text(text: &str, language: &str) -> String {
    let tag_match_regex = regex::Regex::new(r"<.*?>").unwrap();
    let text = tag_match_regex.replace_all(text, "");

    let text = text.replace("\\n", "\n")
        .replace("\\'", "'")
        .replace("\\@", "@")
        .replace("\\?", "?")
        .replace("\\\"", "\"");

    form_urlencoded::Serializer::new(String::new())
        .append_pair("q", &text)
        .finish()
}

async fn deserialize_text(text: &str) -> String {
    let text = text.replace(r"\ ", "\\")
        .replace(r"\ n ", "\\n")
        .replace(r"\\n ", "\\n")
        .replace(r"/ ", "/")
        .replace("\n", "\\n")
        .replace("@", "\\@")
        .replace("?", "\\?")
        .replace("\"", "\\\"");
    text
}

async fn translate(to_translate: &str, to_language: &str, language: &str) -> Option<String> {
    match translate_internal(to_translate, to_language, language).await {
        Ok(result) => {
            println!("Success");
            Some(result)
        }
        Err(e) => {
            println!("Exception: {}", e);
            None
        }
    }
}

async fn translate_internal(to_translate: &str, to_language: &str, language: &str) -> Result<String, Box<dyn std::error::Error>> {
    let to_translate = serialize_text(to_translate, language).await;
    let client = Client::new();
    let translate_url = format!("https://translate.google.com/m?sl={}&tl={}&q={}", language, to_language, to_translate.replace(" ", "+"));
    let response = client.get(&translate_url).send().await?;
    let text = response.text().await?;
    let text_encoding = response.encoding().unwrap().to_string();

    handle_charset_conflict(&text_encoding, &text).await;

    let parsed_translation = extract_translation(&text).await;
    let fixed_translation = fix_parameter_strings(&parsed_translation).await;
    Ok(fixed_translation)
}

async fn handle_charset_conflict(text_encoding: &str, text: &str) {
    let charset_start = text.find("charset=").unwrap_or(0) + "charset=".len();
    let charset_end = text.find('"', charset_start).unwrap_or(text.len());
    let detected_encoding = &text[charset_start..charset_end];
    if text_encoding != detected_encoding {
        println!("\x1b[1;31;40mWarning: Potential Charset conflict");
        println!(" Encoding as extracted by SELF    : {}", text_encoding);
        println!(" Encoding as detected by REQUESTS : {}\x1b[0m", detected_encoding);
    }
}

async fn extract_translation(text: &str) -> String {
    let before_trans = "class=\"result-container\">";
    let after_trans = "</div>";
    let parsed1 = &text[text.find(before_trans).unwrap_or(0) + before_trans.len()..];
    let parsed2 = &parsed1[..parsed1.find(after_trans).unwrap_or(parsed1.len())];
    deserialize_text(html_escape::decode_html_entities(parsed2).as_str()).await
}

async fn fix_parameter_strings(parsed_translation: &str) -> String {
    let parsed3 = regex::Regex::new(r"% ([ds])")
        .unwrap()
        .replace_all(parsed_translation, " %\\1");
    let parsed4 = regex::Regex::new(r"% ([\d]) \$ ([ds])")
        .unwrap()
        .replace_all(&parsed3, " %\\1$\\2")
        .trim()
        .to_string();
    deserialize_text(html_escape::decode_html_entities(&parsed4).as_str()).await
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = env::args().collect();
    let infile = args.get(1).unwrap_or(&"strings.xml".to_string());
    let input_language = args.get(2).unwrap_or(&"en".to_string());
    let output_langs: Vec<_> = args.get(3..).unwrap_or(&[
        "af", "sq", "am", "ar", "hy", "az", "eu", "be", "bn", "bs", "bg", "ca", "ceb", "ny", "zh-CN", "co", "hr", "cs", "da", "nl", "en", "eo", "et", "tl", "fi", "fr", "fy", "gl", "ka", "de", "el", "gu", "ht", "ha", "haw", "iw", "hi", "hmn", "hu", "is", "ig", "id", "ga", "it", "ja", "jw", "kn", "kk", "km", "rw", "ko", "ku", "ky", "lo", "la", "lv", "lt", "lb", "mk", "mg", "ms", "ml", "mt", "mi", "mr", "mn", "my", "ne", "no", "or", "ps", "fa", "pl", "pt", "pa", "ro", "ru", "sm", "gd", "sr", "st", "sn", "sd", "si", "sk", "sl", "so", "es", "su", "sw", "sv", "tg", "ta", "tt", "te", "th", "tr", "tk", "uk", "ur", "ug", "uz", "vi", "cy", "xh", "yi", "yo", "zu",
    ]).to_vec();

    let out_directory = Path::new("out");
    if out_directory.exists() {
        fs::remove_dir_all(out_directory).unwrap();
    }
    fs::create_dir(out_directory).unwrap();

    let mut tasks = Vec::new();
    for output_lang in &output_langs {
        let output_dir = out_directory.join(format!("values-{}", output_lang));
        fs::create_dir(&output_dir).unwrap();
        let output_file = output_dir.join("strings.xml");
        tasks.push(perform_translate(
            &infile,
            &output_lang,
            &input_language,
            &output_file,
        ));
    }

    futures::future::join_all(tasks).await;
    println!("done");
}

async fn perform_translate(
    infile: &str,
    output_lang: &str,
    input_language: &str,
    output_file: &Path,
) {
    let tree = xml::reader::EventReader::new(fs::File::open(infile).unwrap())
        .into_iter()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();

    println!("{}...\n", output_lang);

    let mut writer = EventWriter::new_with_config(
        fs::File::create(output_file).unwrap(),
        EmitterConfig::new().perform_indent(true),
    );

    writer.write(XmlEvent::StartDocument {
        version: xml::writer::XmlVersion::Version10,
        encoding: Some("utf-8"),
    })
    .unwrap();
    writer.write(XmlEvent::StartElement {
        name: "resources".to_string(),
        attributes: Vec::new(),
    })
    .unwrap();

    for event in tree {
        match event {
            xml::reader::XmlEvent::StartElement {
                name,
                attributes,
                ..
            } => {
                writer
                    .write(XmlEvent::StartElement {
                        name: name.local_name,
                        attributes,
                    })
                    .unwrap();
            }
            xml::reader::XmlEvent::EndElement { name } => {
                writer.write(XmlEvent::EndElement { name }).unwrap();
            }
            xml::reader::XmlEvent::Characters(text) => {
                if let Some(element) = writer.get_element() {
                    if element.name == "string" && element.attributes.get("translatable") != Some(&"false".to_string()) {
                        let translated = translate(&text, output_lang, input_language)
                            .await
                            .unwrap_or(text);
                        writer.write(XmlEvent::Characters(translated)).unwrap();
                    } else {
                        writer.write(XmlEvent::Characters(text)).unwrap();
                    }
                } else {
                    writer.write(XmlEvent::Characters(text)).unwrap();
                }
            }
            _ => {}
        }
    }

    writer
        .write(XmlEvent::EndElement {
            name: "resources".to_string(),
        })
        .unwrap();
    writer.write(XmlEvent::EndDocument).unwrap();
        }
