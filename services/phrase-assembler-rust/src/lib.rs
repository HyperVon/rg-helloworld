use sha2::{Digest, Sha256};

pub const VERSION: &str = "0.5.0-milestone11";
pub const SERVICE_NAME: &str = "phrase-assembler";
pub const OTEL_SERVICE_NAME: &str = "phrase-assembler";
pub const OTEL_COLLECTOR_ENDPOINT: &str = "http://otel-collector.rube-goldberg:4317";
pub const INPUT_MATURITY: i32 = 80;
pub const OUTPUT_MATURITY: i32 = 90;

#[derive(Debug, Clone, PartialEq, Eq, serde::Deserialize)]
pub enum TokenType {
    Symbol,
    Gap,
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct AdjudicatedToken {
    pub position: i32,
    #[serde(rename = "tokenType")]
    pub token_type: TokenType,
    pub utf8: String,
    pub confidence: f64,
    #[serde(rename = "inputArtifact")]
    pub input_artifact: String,
    #[serde(default)]
    pub run_id: Option<String>,
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct Transformation {
    pub name: String,
    pub version: String,
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct SymbolData {
    #[serde(rename = "tokenType")]
    pub token_type: String,
    pub utf8: String,
    pub confidence: f64,
    pub evidence: serde_json::Value,
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct SymbolAdjudicatedData {
    #[serde(rename = "runId")]
    pub run_id: String,
    #[serde(rename = "stepId")]
    pub step_id: String,
    #[serde(rename = "glyphInstanceId")]
    pub glyph_instance_id: String,
    pub position: i32,
    pub attempt: i32,
    #[serde(rename = "inputMaturity")]
    pub input_maturity: i32,
    #[serde(rename = "outputMaturity")]
    pub output_maturity: i32,
    #[serde(rename = "inputArtifacts")]
    pub input_artifacts: Vec<String>,
    #[serde(rename = "outputArtifacts")]
    pub output_artifacts: Vec<String>,
    pub transformation: Transformation,
    pub symbol: SymbolData,
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct SymbolAdjudicatedEvent {
    #[serde(rename = "specversion")]
    pub specversion: String,
    pub id: String,
    pub source: String,
    #[serde(rename = "type")]
    pub event_type: String,
    pub subject: String,
    pub time: String,
    #[serde(rename = "datacontenttype")]
    pub datacontenttype: String,
    #[serde(rename = "correlationid")]
    pub correlationid: String,
    pub data: SymbolAdjudicatedData,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct AssemblyManifest {
    pub positions: Vec<PositionManifest>,
    pub total_bytes: usize,
    pub sha256: String,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct PositionManifest {
    pub position: i32,
    pub byte_range: ByteRange,
    pub evidence_artifact: String,
    pub token_type: String,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ByteRange {
    pub start: usize,
    pub end: usize,
}

#[derive(Debug)]
pub enum AssemblyError {
    DuplicatePosition(i32),
    MissingPosition(i32),
    InvalidUtf8,
    EmptyInput,
}

impl std::fmt::Display for AssemblyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AssemblyError::DuplicatePosition(pos) => write!(f, "duplicate position: {}", pos),
            AssemblyError::MissingPosition(pos) => write!(f, "missing position: {}", pos),
            AssemblyError::InvalidUtf8 => write!(f, "assembled text is not valid UTF-8"),
            AssemblyError::EmptyInput => write!(f, "no tokens provided"),
        }
    }
}

impl std::error::Error for AssemblyError {}

pub fn banner() -> String {
    format!("{SERVICE_NAME} {VERSION} (Milestone 11)")
}

pub fn assemble(
    tokens: Vec<AdjudicatedToken>,
) -> Result<(String, AssemblyManifest), AssemblyError> {
    if tokens.is_empty() {
        return Err(AssemblyError::EmptyInput);
    }

    let mut seen_positions: std::collections::HashSet<i32> = std::collections::HashSet::new();
    let mut sorted = tokens.clone();
    sorted.sort_by_key(|t| t.position);

    for token in &sorted {
        if !seen_positions.insert(token.position) {
            return Err(AssemblyError::DuplicatePosition(token.position));
        }
    }

    let actual_positions: std::collections::HashSet<i32> =
        sorted.iter().map(|t| t.position).collect();
    for pos in 0..sorted.len() as i32 {
        if !actual_positions.contains(&pos) {
            return Err(AssemblyError::MissingPosition(pos));
        }
    }

    let mut byte_buffer: Vec<u8> = Vec::new();
    let mut position_manifests: Vec<PositionManifest> = Vec::new();

    for token in &sorted {
        let start = byte_buffer.len();
        byte_buffer.extend_from_slice(token.utf8.as_bytes());
        let end = byte_buffer.len();

        position_manifests.push(PositionManifest {
            position: token.position,
            byte_range: ByteRange { start, end },
            evidence_artifact: token.input_artifact.clone(),
            token_type: match token.token_type {
                TokenType::Symbol => "SYMBOL",
                TokenType::Gap => "GAP",
            }
            .to_string(),
        });
    }

    let text = String::from_utf8(byte_buffer.clone()).map_err(|_| AssemblyError::InvalidUtf8)?;
    let mut hasher = Sha256::new();
    hasher.update(&byte_buffer);
    let sha256 = format!("{:x}", hasher.finalize());

    let manifest = AssemblyManifest {
        positions: position_manifests,
        total_bytes: byte_buffer.len(),
        sha256: sha256.clone(),
    };

    Ok((text, manifest))
}

pub fn build_assembly_event(
    run_id: String,
    step_id: String,
    attempt: i32,
    assembled_text: &str,
    sha256: &str,
    input_artifacts: Vec<String>,
    output_artifacts: Vec<String>,
) -> String {
    let operation_id = build_operation_id(&run_id, &step_id, attempt, sha256);
    let manifest_stub = AssemblyManifest {
        positions: vec![],
        total_bytes: assembled_text.len(),
        sha256: sha256.to_string(),
    };
    let provenance_ws = build_provenance_attestation(
        &run_id,
        &step_id,
        attempt,
        &manifest_stub,
        &input_artifacts,
        &output_artifacts,
    );
    let mut hasher = Sha256::new();
    hasher.update(provenance_ws.as_bytes());
    let provenance_sha256 = format!("{:x}", hasher.finalize());
    if let Err(e) =
        verify_provenance_attestation(&provenance_ws, &manifest_stub, &run_id, &step_id, attempt)
    {
        eprintln!("warning: provenance self-check failed: {}", e);
    }
    let event = serde_json::json!({
        "specversion": "1.0",
        "id": operation_id,
        "source": SERVICE_NAME,
        "type": "rg.phrase-assembled.v1",
        "subject": format!("runs/{}", run_id),
        "time": std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| format!("{}.000Z", d.as_secs()))
            .unwrap_or_default(),
        "datacontenttype": "application/json",
        "correlationid": run_id,
        "data": {
            "runId": run_id,
            "stepId": step_id,
            "attempt": attempt,
            "inputMaturity": INPUT_MATURITY,
            "outputMaturity": OUTPUT_MATURITY,
            "inputArtifacts": input_artifacts,
            "outputArtifacts": output_artifacts,
            "transformation": {
                "name": "assemble-phrase",
                "version": "1.0"
            },
            "assembledText": assembled_text,
            "sha256": sha256,
            "provenanceAttestation": provenance_ws,
            "provenanceSha256": provenance_sha256
        }
    });
    serde_json::to_string_pretty(&event).unwrap_or_default()
}

pub fn build_operation_id(run_id: &str, step_id: &str, attempt: i32, input_hash: &str) -> String {
    let payload = format!(
        "{{\"runId\":\"{}\",\"stepId\":\"{}\",\"attempt\":{},\"input\":\"{}\"}}",
        run_id, step_id, attempt, input_hash
    );
    let mut hasher = Sha256::new();
    hasher.update(payload.as_bytes());
    format!("{:x}", hasher.finalize())
}

pub fn check_prohibited_fields(event_json: &str) -> Vec<String> {
    let prohibited = [
        "message",
        "targetText",
        "expectedCharacter",
        "unicodeCodePoint",
        "characterName",
        "glyphLabel",
    ];
    prohibited
        .iter()
        .filter(|field| event_json.contains(&format!("\"{}\"", field)))
        .map(|s| s.to_string())
        .collect()
}

pub fn symbol_adjudicated_to_token(data: &SymbolAdjudicatedData) -> AdjudicatedToken {
    let token_type = match data.symbol.token_type.as_str() {
        "GAP" => TokenType::Gap,
        _ => TokenType::Symbol,
    };
    let input_artifact = data.input_artifacts.first().cloned().unwrap_or_default();
    AdjudicatedToken {
        position: data.position,
        token_type,
        utf8: data.symbol.utf8.clone(),
        confidence: data.symbol.confidence,
        input_artifact,
        run_id: Some(data.run_id.clone()),
    }
}

pub fn run_assemble_once(
    input_path: &str,
    output_path: Option<&str>,
    event_output_path: Option<&str>,
) -> Result<String, String> {
    let input_content =
        std::fs::read_to_string(input_path).map_err(|e| format!("cannot read input: {}", e))?;
    let tokens: Vec<AdjudicatedToken> =
        serde_json::from_str(&input_content).map_err(|e| format!("cannot parse tokens: {}", e))?;

    let (text, manifest) = assemble(tokens.clone()).map_err(|e| e.to_string())?;

    if let Some(path) = output_path {
        let manifest_json = serde_json::to_string_pretty(&manifest).map_err(|e| e.to_string())?;
        std::fs::write(path, manifest_json).map_err(|e| e.to_string())?;
    }

    if let Some(path) = event_output_path {
        let input_artifacts: Vec<String> =
            tokens.iter().map(|t| t.input_artifact.clone()).collect();
        let provenance_ws = build_provenance_attestation(
            "test-run",
            "test-step",
            1,
            &manifest,
            &input_artifacts,
            &[path.to_string()],
        );
        verify_provenance_attestation(&provenance_ws, &manifest, "test-run", "test-step", 1)
            .map_err(|e| format!("provenance validation failed: {}", e))?;
        let provenance_path = format!("{}.ws", path);
        std::fs::write(&provenance_path, &provenance_ws).map_err(|e| e.to_string())?;
        let mut sidecar_hasher = Sha256::new();
        sidecar_hasher.update(provenance_ws.as_bytes());
        let sidecar_sha = format!("{:x}", sidecar_hasher.finalize());
        eprintln!(
            "provenance sidecar: {} (sha256={}, key={})",
            provenance_path,
            sidecar_sha,
            provenance_sidecar_object_key("test-run", "test-step", 1, &manifest.sha256)
        );
        let event = build_assembly_event(
            "test-run".to_string(),
            "test-step".to_string(),
            1,
            &text,
            &manifest.sha256,
            input_artifacts,
            vec![path.to_string()],
        );
        std::fs::write(path, event).map_err(|e| e.to_string())?;
    }

    Ok(text)
}

pub fn verify_provenance_attestation(
    ws: &str,
    manifest: &AssemblyManifest,
    run_id: &str,
    step_id: &str,
    attempt: i32,
) -> Result<(), String> {
    if ws.len() > 8192 {
        return Err("provenance attestation exceeds max size".into());
    }
    let decoded = whitespace::decode(ws).map_err(|e| e.to_string())?;
    if !decoded.contains(&format!("runId={}", run_id)) {
        return Err("provenance runId mismatch".into());
    }
    if !decoded.contains(&format!("stepId={}", step_id)) {
        return Err("provenance stepId mismatch".into());
    }
    if !decoded.contains(&format!("attempt={}", attempt)) {
        return Err("provenance attempt mismatch".into());
    }
    if !decoded.contains(&format!("sha256={}", manifest.sha256)) {
        return Err("provenance sha256 mismatch".into());
    }
    if !decoded.contains(&format!("maturity={}->{}", INPUT_MATURITY, OUTPUT_MATURITY)) {
        return Err("provenance maturity mismatch".into());
    }
    Ok(())
}

pub fn provenance_sidecar_object_key(
    run_id: &str,
    step_id: &str,
    attempt: i32,
    sha256: &str,
) -> String {
    let suffix = build_operation_id(run_id, step_id, attempt, sha256);
    format!("runs/{}/provenance/{}.ws", run_id, suffix)
}

pub mod whitespace;

pub fn build_provenance_attestation(
    run_id: &str,
    step_id: &str,
    attempt: i32,
    manifest: &AssemblyManifest,
    input_artifacts: &[String],
    output_artifacts: &[String],
) -> String {
    let attestation = format!(
        "runId={} stepId={} attempt={} maturity={}->{} sha256={} input_count={} output_count={}",
        run_id,
        step_id,
        attempt,
        INPUT_MATURITY,
        OUTPUT_MATURITY,
        manifest.sha256,
        input_artifacts.len(),
        output_artifacts.len()
    );
    whitespace::encode(&attestation)
}

pub fn kafka_bootstrap() -> String {
    std::env::var("KAFKA_BOOTSTRAP")
        .unwrap_or_else(|_| "kafka.rube-goldberg.svc.cluster.local:9092".to_string())
}

pub fn input_topic() -> String {
    std::env::var("ASSEMBLER_INPUT_TOPIC")
        .unwrap_or_else(|_| "rg.symbols-adjudicated.v1".to_string())
}

pub fn output_topic() -> String {
    std::env::var("ASSEMBLER_OUTPUT_TOPIC").unwrap_or_else(|_| "rg.phrase-assembled.v1".to_string())
}

pub fn group_id() -> String {
    std::env::var("KAFKA_GROUP_ID").unwrap_or_else(|_| "phrase-assembler-v1".to_string())
}

pub fn otel_endpoint() -> String {
    std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT")
        .ok()
        .filter(|endpoint| !endpoint.trim().is_empty())
        .unwrap_or_else(|| OTEL_COLLECTOR_ENDPOINT.to_string())
}

pub fn process_adjudicated_payload(payload: &[u8]) -> Result<AdjudicatedToken, String> {
    let event: SymbolAdjudicatedEvent =
        serde_json::from_slice(payload).map_err(|e| format!("parse failed: {}", e))?;
    if event.event_type != "rg.symbols-adjudicated.v1" {
        return Err("invalid event type".into());
    }
    if event.data.input_maturity != 70 || event.data.output_maturity != 80 {
        return Err(format!(
            "invalid maturity: {} -> {}",
            event.data.input_maturity, event.data.output_maturity
        ));
    }
    Ok(symbol_adjudicated_to_token(&event.data))
}

pub fn flush_run_buffer(
    run_id: String,
    tokens: Vec<AdjudicatedToken>,
) -> Result<(String, String), String> {
    let (text, manifest) = assemble(tokens).map_err(|e| e.to_string())?;
    let input_artifacts: Vec<String> = manifest
        .positions
        .iter()
        .map(|p| p.evidence_artifact.clone())
        .collect();
    let output_artifacts = vec![manifest.sha256.clone()];
    let provenance_ws = build_provenance_attestation(
        &run_id,
        "assembled-step",
        1,
        &manifest,
        &input_artifacts,
        &output_artifacts,
    );
    verify_provenance_attestation(&provenance_ws, &manifest, &run_id, "assembled-step", 1)
        .map_err(|e| format!("provenance validation failed: {}", e))?;
    let event_json = build_assembly_event(
        run_id.clone(),
        "assembled-step".to_string(),
        1,
        &text,
        &manifest.sha256,
        input_artifacts,
        output_artifacts,
    );
    Ok((text, event_json))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;
    use std::sync::Mutex;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn kafka_bootstrap_default() {
        let _guard = ENV_LOCK.lock().unwrap();
        unsafe {
            env::remove_var("KAFKA_BOOTSTRAP");
        }
        assert_eq!(
            kafka_bootstrap(),
            "kafka.rube-goldberg.svc.cluster.local:9092"
        );
    }

    #[test]
    fn kafka_bootstrap_override() {
        let _guard = ENV_LOCK.lock().unwrap();
        unsafe {
            env::set_var("KAFKA_BOOTSTRAP", "custom:9092");
        }
        assert_eq!(kafka_bootstrap(), "custom:9092");
        unsafe {
            env::remove_var("KAFKA_BOOTSTRAP");
        }
    }

    #[test]
    fn input_topic_default() {
        let _guard = ENV_LOCK.lock().unwrap();
        unsafe {
            env::remove_var("ASSEMBLER_INPUT_TOPIC");
        }
        assert_eq!(input_topic(), "rg.symbols-adjudicated.v1");
    }

    #[test]
    fn input_topic_override() {
        let _guard = ENV_LOCK.lock().unwrap();
        unsafe {
            env::set_var("ASSEMBLER_INPUT_TOPIC", "custom-topic");
        }
        assert_eq!(input_topic(), "custom-topic");
        unsafe {
            env::remove_var("ASSEMBLER_INPUT_TOPIC");
        }
    }

    #[test]
    fn output_topic_default() {
        let _guard = ENV_LOCK.lock().unwrap();
        unsafe {
            env::remove_var("ASSEMBLER_OUTPUT_TOPIC");
        }
        assert_eq!(output_topic(), "rg.phrase-assembled.v1");
    }

    #[test]
    fn output_topic_override() {
        let _guard = ENV_LOCK.lock().unwrap();
        unsafe {
            env::set_var("ASSEMBLER_OUTPUT_TOPIC", "custom-out");
        }
        assert_eq!(output_topic(), "custom-out");
        unsafe {
            env::remove_var("ASSEMBLER_OUTPUT_TOPIC");
        }
    }

    #[test]
    fn group_id_default() {
        let _guard = ENV_LOCK.lock().unwrap();
        unsafe {
            env::remove_var("KAFKA_GROUP_ID");
        }
        assert_eq!(group_id(), "phrase-assembler-v1");
    }

    #[test]
    fn group_id_override() {
        let _guard = ENV_LOCK.lock().unwrap();
        unsafe {
            env::set_var("KAFKA_GROUP_ID", "custom-group");
        }
        assert_eq!(group_id(), "custom-group");
        unsafe {
            env::remove_var("KAFKA_GROUP_ID");
        }
    }

    #[test]
    fn otel_endpoint_default() {
        let _guard = ENV_LOCK.lock().unwrap();
        unsafe {
            env::remove_var("OTEL_EXPORTER_OTLP_ENDPOINT");
        }
        assert_eq!(otel_endpoint(), OTEL_COLLECTOR_ENDPOINT);
    }

    #[test]
    fn otel_endpoint_override() {
        let _guard = ENV_LOCK.lock().unwrap();
        unsafe {
            env::set_var("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317");
        }
        assert_eq!(otel_endpoint(), "http://localhost:4317");
        unsafe {
            env::remove_var("OTEL_EXPORTER_OTLP_ENDPOINT");
        }
    }

    #[test]
    fn otel_endpoint_ignores_blank_override() {
        let _guard = ENV_LOCK.lock().unwrap();
        unsafe {
            env::set_var("OTEL_EXPORTER_OTLP_ENDPOINT", "   ");
        }
        assert_eq!(otel_endpoint(), OTEL_COLLECTOR_ENDPOINT);
        unsafe {
            env::remove_var("OTEL_EXPORTER_OTLP_ENDPOINT");
        }
    }

    #[test]
    fn process_adjudicated_payload_valid() {
        let payload = r#"{
            "specversion": "1.0",
            "id": "event-1",
            "source": "adjudicator",
            "type": "rg.symbols-adjudicated.v1",
            "subject": "runs/run-1",
            "time": "2026-01-01T00:00:00Z",
            "datacontenttype": "application/json",
            "correlationid": "run-1",
            "data": {
                "runId": "run-1",
                "stepId": "step-1",
                "glyphInstanceId": "glyph-0",
                "position": 0,
                "attempt": 1,
                "inputMaturity": 70,
                "outputMaturity": 80,
                "inputArtifacts": ["artifact-1"],
                "outputArtifacts": [],
                "transformation": {"name": "adjudicate-symbol", "version": "1.0"},
                "symbol": {
                    "tokenType": "SYMBOL",
                    "utf8": "H",
                    "confidence": 0.95,
                    "evidence": {"agreement": true}
                }
            }
        }"#;
        let token = process_adjudicated_payload(payload.as_bytes()).unwrap();
        assert_eq!(token.position, 0);
        assert_eq!(token.utf8, "H");
        assert_eq!(token.run_id, Some("run-1".to_string()));
    }

    #[test]
    fn process_adjudicated_payload_invalid_type() {
        let payload = r#"{
            "specversion": "1.0",
            "id": "event-1",
            "source": "adjudicator",
            "type": "rg.wrong-event.v1",
            "subject": "runs/run-1",
            "time": "2026-01-01T00:00:00Z",
            "datacontenttype": "application/json",
            "correlationid": "run-1",
            "data": {
                "runId": "run-1",
                "stepId": "step-1",
                "glyphInstanceId": "glyph-0",
                "position": 0,
                "attempt": 1,
                "inputMaturity": 70,
                "outputMaturity": 80,
                "inputArtifacts": ["artifact-1"],
                "outputArtifacts": [],
                "transformation": {"name": "adjudicate-symbol", "version": "1.0"},
                "symbol": {
                    "tokenType": "SYMBOL",
                    "utf8": "H",
                    "confidence": 0.95,
                    "evidence": {"agreement": true}
                }
            }
        }"#;
        assert!(process_adjudicated_payload(payload.as_bytes()).is_err());
    }

    #[test]
    fn process_adjudicated_payload_invalid_maturity() {
        let payload = r#"{
            "specversion": "1.0",
            "id": "event-1",
            "source": "adjudicator",
            "type": "rg.symbols-adjudicated.v1",
            "subject": "runs/run-1",
            "time": "2026-01-01T00:00:00Z",
            "datacontenttype": "application/json",
            "correlationid": "run-1",
            "data": {
                "runId": "run-1",
                "stepId": "step-1",
                "glyphInstanceId": "glyph-0",
                "position": 0,
                "attempt": 1,
                "inputMaturity": 60,
                "outputMaturity": 70,
                "inputArtifacts": ["artifact-1"],
                "outputArtifacts": [],
                "transformation": {"name": "adjudicate-symbol", "version": "1.0"},
                "symbol": {
                    "tokenType": "SYMBOL",
                    "utf8": "H",
                    "confidence": 0.95,
                    "evidence": {"agreement": true}
                }
            }
        }"#;
        assert!(process_adjudicated_payload(payload.as_bytes()).is_err());
    }

    #[test]
    fn flush_run_buffer_assembles_tokens() {
        let tokens = vec![
            AdjudicatedToken {
                position: 0,
                token_type: TokenType::Symbol,
                utf8: "H".to_string(),
                confidence: 0.9,
                input_artifact: "a1".to_string(),
                run_id: None,
            },
            AdjudicatedToken {
                position: 1,
                token_type: TokenType::Symbol,
                utf8: "i".to_string(),
                confidence: 0.9,
                input_artifact: "a2".to_string(),
                run_id: None,
            },
        ];
        let (text, event) = flush_run_buffer("run-1".to_string(), tokens).unwrap();
        assert_eq!(text, "Hi");
        let parsed: serde_json::Value = serde_json::from_str(&event).unwrap();
        assert_eq!(parsed["data"]["assembledText"], "Hi");
    }

    #[test]
    fn flush_run_buffer_rejects_duplicates() {
        let tokens = vec![
            AdjudicatedToken {
                position: 0,
                token_type: TokenType::Symbol,
                utf8: "H".to_string(),
                confidence: 0.9,
                input_artifact: "a1".to_string(),
                run_id: None,
            },
            AdjudicatedToken {
                position: 0,
                token_type: TokenType::Symbol,
                utf8: "i".to_string(),
                confidence: 0.9,
                input_artifact: "a2".to_string(),
                run_id: None,
            },
        ];
        assert!(flush_run_buffer("run-1".to_string(), tokens).is_err());
    }

    #[test]
    fn build_operation_id_deterministic() {
        let id = build_operation_id("run-1", "step-1", 1, "abc");
        assert_eq!(id.len(), 64);
        assert!(id.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn check_prohibited_fields_detects_violations() {
        let event = r#"{"targetText":"Hello","expectedCharacter":"H"}"#;
        let found = check_prohibited_fields(event);
        assert!(found.contains(&"targetText".to_string()));
        assert!(found.contains(&"expectedCharacter".to_string()));
    }

    #[test]
    fn check_prohibited_fields_clean_event() {
        let event = r#"{"specversion":"1.0","data":{"assembledText":"Hi"}}"#;
        let found = check_prohibited_fields(event);
        assert!(found.is_empty());
    }

    #[test]
    fn assemble_missing_position() {
        let tokens = vec![
            AdjudicatedToken {
                position: 0,
                token_type: TokenType::Symbol,
                utf8: "H".to_string(),
                confidence: 0.9,
                input_artifact: "a1".to_string(),
                run_id: None,
            },
            AdjudicatedToken {
                position: 2,
                token_type: TokenType::Symbol,
                utf8: "i".to_string(),
                confidence: 0.9,
                input_artifact: "a2".to_string(),
                run_id: None,
            },
        ];
        let result = assemble(tokens);
        assert!(result.is_err());
    }

    #[test]
    fn build_provenance_attestation_whitespace() {
        let manifest = AssemblyManifest {
            positions: vec![],
            total_bytes: 0,
            sha256: "abc".to_string(),
        };
        let attestation = build_provenance_attestation("run-1", "step-1", 1, &manifest, &[], &[]);
        assert!(!attestation.is_empty());
        let decoded = whitespace::decode(&attestation).unwrap_or_default();
        assert!(decoded.contains("runId=run-1"));
    }

    #[test]
    fn verify_provenance_attestation_valid() {
        let manifest = AssemblyManifest {
            positions: vec![],
            total_bytes: 11,
            sha256: "deadbeef".to_string(),
        };
        let ws = build_provenance_attestation("run-1", "step-1", 1, &manifest, &[], &[]);
        assert!(verify_provenance_attestation(&ws, &manifest, "run-1", "step-1", 1).is_ok());
    }

    #[test]
    fn verify_provenance_attestation_runid_mismatch() {
        let manifest = AssemblyManifest {
            positions: vec![],
            total_bytes: 0,
            sha256: "abc".to_string(),
        };
        let ws = build_provenance_attestation("run-1", "step-1", 1, &manifest, &[], &[]);
        let err =
            verify_provenance_attestation(&ws, &manifest, "other-run", "step-1", 1).unwrap_err();
        assert!(err.contains("runId"));
    }

    #[test]
    fn verify_provenance_attestation_stepid_mismatch() {
        let manifest = AssemblyManifest {
            positions: vec![],
            total_bytes: 0,
            sha256: "abc".to_string(),
        };
        let ws = build_provenance_attestation("run-1", "step-1", 1, &manifest, &[], &[]);
        let err =
            verify_provenance_attestation(&ws, &manifest, "run-1", "other-step", 1).unwrap_err();
        assert!(err.contains("stepId"));
    }

    #[test]
    fn verify_provenance_attestation_attempt_mismatch() {
        let manifest = AssemblyManifest {
            positions: vec![],
            total_bytes: 0,
            sha256: "abc".to_string(),
        };
        let ws = build_provenance_attestation("run-1", "step-1", 1, &manifest, &[], &[]);
        let err = verify_provenance_attestation(&ws, &manifest, "run-1", "step-1", 2).unwrap_err();
        assert!(err.contains("attempt"));
    }

    #[test]
    fn verify_provenance_attestation_sha_mismatch() {
        let manifest = AssemblyManifest {
            positions: vec![],
            total_bytes: 0,
            sha256: "abc".to_string(),
        };
        let ws = build_provenance_attestation("run-1", "step-1", 1, &manifest, &[], &[]);
        let bad_manifest = AssemblyManifest {
            positions: vec![],
            total_bytes: 0,
            sha256: "different".to_string(),
        };
        let err =
            verify_provenance_attestation(&ws, &bad_manifest, "run-1", "step-1", 1).unwrap_err();
        assert!(err.contains("sha256"));
    }

    #[test]
    fn verify_provenance_attestation_maturity_mismatch() {
        let manifest = AssemblyManifest {
            positions: vec![],
            total_bytes: 0,
            sha256: "abc".to_string(),
        };
        let ws = whitespace::encode(
            "runId=run-1 stepId=step-1 attempt=1 maturity=0->0 sha256=abc input_count=0 output_count=0",
        );
        let err = verify_provenance_attestation(&ws, &manifest, "run-1", "step-1", 1).unwrap_err();
        assert!(err.contains("maturity"));
    }

    #[test]
    fn verify_provenance_attestation_too_large() {
        let manifest = AssemblyManifest {
            positions: vec![],
            total_bytes: 0,
            sha256: "abc".to_string(),
        };
        let large_ws = " ".repeat(8193);
        let err =
            verify_provenance_attestation(&large_ws, &manifest, "run-1", "step-1", 1).unwrap_err();
        assert!(err.contains("exceeds"));
    }

    #[test]
    fn verify_provenance_attestation_invalid_whitespace() {
        let manifest = AssemblyManifest {
            positions: vec![],
            total_bytes: 0,
            sha256: "abc".to_string(),
        };
        let err =
            verify_provenance_attestation("invalid", &manifest, "run-1", "step-1", 1).unwrap_err();
        assert!(!err.is_empty());
    }

    #[test]
    fn provenance_sidecar_object_key_deterministic() {
        let k1 = provenance_sidecar_object_key("run-1", "step-1", 1, "abc");
        let k2 = provenance_sidecar_object_key("run-1", "step-1", 1, "abc");
        assert_eq!(k1, k2);
        assert!(k1.starts_with("runs/run-1/provenance/"));
        assert!(k1.ends_with(".ws"));
    }

    #[test]
    fn provenance_sidecar_object_key_differs_on_input() {
        let k1 = provenance_sidecar_object_key("run-1", "step-1", 1, "abc");
        let k2 = provenance_sidecar_object_key("run-1", "step-1", 1, "def");
        assert_ne!(k1, k2);
    }

    #[test]
    fn build_assembly_event_contains_provenance() {
        let event = build_assembly_event(
            "run-1".to_string(),
            "step-1".to_string(),
            1,
            "HELLO",
            "abc123",
            vec!["in1".to_string()],
            vec!["out1".to_string()],
        );
        let v: serde_json::Value = serde_json::from_str(&event).unwrap();
        assert_eq!(v["data"]["assembledText"], "HELLO");
        assert!(v["data"]["provenanceAttestation"].is_string());
        assert!(v["data"]["provenanceSha256"].is_string());
        assert_eq!(v["data"]["provenanceSha256"].as_str().unwrap().len(), 64);
    }

    #[test]
    fn run_assemble_once_writes_outputs() {
        let dir = std::env::temp_dir();
        let input_path = dir.join(format!("rghw_test_input_{}.json", uuid::Uuid::new_v4()));
        let output_path = dir.join(format!("rghw_test_output_{}.json", uuid::Uuid::new_v4()));
        let event_path = dir.join(format!("rghw_test_event_{}.json", uuid::Uuid::new_v4()));
        let tokens = serde_json::json!([
            {"position": 0, "tokenType": "Symbol", "utf8": "H", "confidence": 0.9, "inputArtifact": "a1"},
            {"position": 1, "tokenType": "Symbol", "utf8": "I", "confidence": 0.9, "inputArtifact": "a2"}
        ]);
        std::fs::write(&input_path, serde_json::to_string(&tokens).unwrap()).unwrap();
        let text = run_assemble_once(
            input_path.to_str().unwrap(),
            Some(output_path.to_str().unwrap()),
            Some(event_path.to_str().unwrap()),
        )
        .unwrap();
        assert_eq!(text, "HI");
        assert!(output_path.exists());
        assert!(event_path.exists());
        let ws_path = format!("{}.ws", event_path.to_str().unwrap());
        assert!(std::path::Path::new(&ws_path).exists());
        let _ = std::fs::remove_file(&input_path);
        let _ = std::fs::remove_file(&output_path);
        let _ = std::fs::remove_file(&event_path);
        let _ = std::fs::remove_file(&ws_path);
    }

    #[test]
    fn run_assemble_once_missing_input_fails() {
        let result = run_assemble_once("/tmp/nonexistent_rghw_test_input.json", None, None);
        assert!(result.is_err());
    }
}
