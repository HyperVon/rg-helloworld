use std::process::Command;

#[test]
fn cli_version_prints_banner() {
    let executable = env!("CARGO_BIN_EXE_phrase-assembler");
    let output = Command::new(executable)
        .arg("version")
        .output()
        .expect("failed to run");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("phrase-assembler"));
    assert!(stdout.contains("milestone11"));
}

#[test]
fn cli_no_args_prints_banner() {
    let executable = env!("CARGO_BIN_EXE_phrase-assembler");
    let output = Command::new(executable).output().expect("failed to run");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("phrase-assembler"));
    assert!(stdout.contains("milestone11"));
}

#[test]
fn cli_once_without_input_errors() {
    let executable = env!("CARGO_BIN_EXE_phrase-assembler");
    let output = Command::new(executable)
        .arg("--once")
        .output()
        .expect("failed to run");
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("--input"));
    assert!(!output.status.success());
}

#[test]
fn cli_once_with_valid_input_no_output() {
    let executable = env!("CARGO_BIN_EXE_phrase-assembler");
    let dir = std::env::temp_dir();
    let input_path = dir.join("cli_test_tokens_noout.json");
    let tokens_json = r#"[{"position":0,"tokenType":"Symbol","utf8":"Hi","confidence":0.9,"inputArtifact":"a1"}]"#;
    std::fs::write(&input_path, tokens_json).unwrap();

    let output = Command::new(executable)
        .arg("--once")
        .arg(format!("--input={}", input_path.display()))
        .output()
        .expect("failed to run");

    let stdout = String::from_utf8_lossy(&output.stdout);
    assert_eq!(stdout.trim(), "Hi");

    std::fs::remove_file(&input_path).ok();
}

#[test]
fn cli_once_with_missing_file_fails() {
    let executable = env!("CARGO_BIN_EXE_phrase-assembler");
    let output = Command::new(executable)
        .arg("--once")
        .arg("--input=/nonexistent/file.json")
        .output()
        .expect("failed to run");
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("assembly failed"));
    assert!(!output.status.success());
}

#[test]
fn cli_no_args_sets_default_log() {
    let executable = env!("CARGO_BIN_EXE_phrase-assembler");
    let output = Command::new(executable)
        .env_remove("RUST_LOG")
        .output()
        .expect("failed to run");
    assert!(output.status.success());
}
