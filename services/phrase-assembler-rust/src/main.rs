use futures_util::stream::StreamExt;
use phrase_assembler::{
    banner, flush_run_buffer, group_id, input_topic, kafka_bootstrap, output_topic,
    process_adjudicated_payload, run_assemble_once,
};
use rdkafka::ClientConfig;
use rdkafka::Message;
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::producer::{FutureProducer, FutureRecord};
use std::collections::HashMap;
use std::env;
use std::process;
use std::time::Duration;
use tokio::time::Instant;

fn init_tracing() {
    if env::var("RUST_LOG").is_err() {
        unsafe {
            env::set_var("RUST_LOG", "info");
        }
    }
    tracing_subscriber::fmt::init();
}

async fn run_kafka_consumer() -> Result<(), Box<dyn std::error::Error>> {
    let bootstrap = kafka_bootstrap();
    let input_topic = input_topic();
    let output_topic = output_topic();
    let group = group_id();

    let consumer: StreamConsumer = ClientConfig::new()
        .set("bootstrap.servers", &bootstrap)
        .set("group.id", &group)
        .set("auto.offset.reset", "earliest")
        .set("enable.auto.commit", "true")
        .create()?;

    consumer.subscribe(&[&input_topic])?;
    tracing::info!(bootstrap = %bootstrap, input_topic = %input_topic, output_topic = %output_topic, group = %group, "starting kafka consumer");

    let producer: FutureProducer = ClientConfig::new()
        .set("bootstrap.servers", &bootstrap)
        .create()?;

    let buffers: HashMap<String, (Vec<phrase_assembler::AdjudicatedToken>, Instant)> =
        HashMap::new();
    let buffers = std::sync::Arc::new(std::sync::Mutex::new(buffers));
    const FLUSH_DELAY: Duration = Duration::from_secs(5);

    let mut consumer_stream = consumer.stream();
    let mut flush_interval = tokio::time::interval(Duration::from_secs(1));

    loop {
        tokio::select! {
            msg = consumer_stream.next() => {
                match msg {
                    Some(Ok(msg)) => {
                        let payload = match msg.payload() {
                            Some(p) => p,
                            None => continue,
                        };
                        match process_adjudicated_payload(payload) {
                            Ok(token) => {
                                let run_id = token.run_id.clone().unwrap_or_default();
                                let mut bufs = buffers.lock().unwrap();
                                let entry = bufs.entry(run_id).or_insert_with(|| (Vec::new(), Instant::now()));
                                entry.0.push(token);
                                entry.1 = Instant::now();
                            }
                            Err(e) => {
                                tracing::warn!(error = %e, "failed to process adjudicated payload");
                            }
                        }
                    }
                    Some(Err(e)) => {
                        tracing::error!(error = %e, "kafka consumer error");
                    }
                    None => {
                        tracing::info!("kafka consumer stream ended");
                        break Ok(());
                    }
                }
            }
            _ = flush_interval.tick() => {
                let mut to_flush = Vec::new();
                {
                    let bufs = buffers.lock().unwrap();
                    let now = Instant::now();
                    for (run_id, (tokens, last)) in bufs.iter() {
                        if now.duration_since(*last) >= FLUSH_DELAY {
                            to_flush.push((run_id.clone(), tokens.clone()));
                        }
                    }
                }
                for (run_id, tokens) in to_flush {
                    {
                        let mut bufs = buffers.lock().unwrap();
                        bufs.remove(&run_id);
                    }
                    match flush_run_buffer(run_id.clone(), tokens) {
                        Ok((text, event_json)) => {
                            let payload = event_json.clone();
                            let record = FutureRecord::to(&output_topic)
                                .key(&run_id)
                                .payload(&payload);
                            if let Err((e, _)) = producer.send(record, Duration::from_secs(5)).await {
                                tracing::error!(error = %e, "failed to publish phrase assembled event");
                            } else {
                                tracing::info!(run_id = %run_id, text = %text, "published phrase assembled");
                            }
                        }
                        Err(e) => {
                            tracing::warn!(run_id = %run_id, error = %e, "assembly failed, dropping run buffer");
                        }
                    }
                }
            }
        }
    }
}

#[derive(Debug)]
enum RunMode {
    Version,
    Once {
        input: String,
        output: Option<String>,
        event_output: Option<String>,
    },
    Run,
    Banner,
}

fn parse_args(args: &[String]) -> RunMode {
    if args.len() > 1 && args[1] == "version" {
        return RunMode::Version;
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
        if let Some(input_path) = input {
            return RunMode::Once {
                input: input_path,
                output,
                event_output,
            };
        }
        eprintln!("--input <path> is required for --once mode");
        process::exit(1);
    }
    if args.len() > 1 && args[1] == "run" {
        return RunMode::Run;
    }
    RunMode::Banner
}

async fn run_mode(mode: RunMode) -> Result<(), String> {
    match mode {
        RunMode::Version => {
            println!("{}", banner());
            Ok(())
        }
        RunMode::Once {
            input,
            output,
            event_output,
        } => {
            let text = run_assemble_once(&input, output.as_deref(), event_output.as_deref())?;
            if output.is_none() && event_output.is_none() {
                println!("{}", text);
            }
            Ok(())
        }
        RunMode::Run => run_kafka_consumer().await.map_err(|e| e.to_string()),
        RunMode::Banner => {
            println!("{}", banner());
            Ok(())
        }
    }
}

#[tokio::main]
async fn main() {
    init_tracing();

    let args: Vec<String> = env::args().collect();
    let mode = parse_args(&args);
    if let Err(e) = run_mode(mode).await {
        eprintln!("assembly failed: {}", e);
        process::exit(1);
    }
}
