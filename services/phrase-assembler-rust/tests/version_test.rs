use phrase_assembler::{SERVICE_NAME, VERSION, banner};

#[test]
fn version_matches_milestone_11() {
    assert_eq!(VERSION, "0.5.0-milestone11");
}

#[test]
fn version_is_not_empty() {
    assert!(!VERSION.is_empty());
}

#[test]
fn service_name_is_set() {
    assert_eq!(SERVICE_NAME, "phrase-assembler");
}

#[test]
fn banner_includes_service_and_version() {
    assert!(banner().starts_with("phrase-assembler 0.5.0-milestone11"));
}

#[test]
fn banner_is_deterministic() {
    assert_eq!(banner(), banner());
}
