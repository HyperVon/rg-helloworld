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
            "sha256": sha256
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
