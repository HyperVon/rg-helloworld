use phrase_assembler::{banner, run_assemble_once};
use std::env;
use std::process;

fn init_tracing() {
    if env::var("RUST_LOG").is_err() {
        unsafe {
            env::set_var("RUST_LOG", "info");
        }
    }
    tracing_subscriber::fmt::init();
}

fn main() {
    init_tracing();

    let args: Vec<String> = env::args().collect();
    if args.len() > 1 && args[1] == "version" {
        println!("{}", banner());
        process::exit(0);
    }

    if args.len() > 1 && args[1] == "--once" {
        let input = args
            .iter()
            .find(|a| a.starts_with("--input="))
            .map(|a| a.strip_prefix("--input=").unwrap().to_string());
        let output = args
            .iter()
            .find(|a| a.starts_with("--output="))
            .map(|a| a.strip_prefix("--output=").unwrap().to_string());
        let event_output = args
            .iter()
            .find(|a| a.starts_with("--event-output="))
            .map(|a| a.strip_prefix("--event-output=").unwrap().to_string());

        let input_path = match input {
            Some(p) => p,
            None => {
                eprintln!("--input <path> is required for --once mode");
                process::exit(1);
            }
        };

        match run_assemble_once(&input_path, output.as_deref(), event_output.as_deref()) {
            Ok(text) => {
                if output.is_none() && event_output.is_none() {
                    println!("{}", text);
                }
            }
            Err(e) => {
                eprintln!("assembly failed: {}", e);
                process::exit(1);
            }
        }
    } else {
        println!("{}", banner());
    }
}
