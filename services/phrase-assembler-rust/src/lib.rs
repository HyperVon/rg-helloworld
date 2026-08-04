pub const VERSION: &str = "0.0.0-skeleton";
pub const SERVICE_NAME: &str = "phrase-assembler";

pub fn banner() -> String {
    format!("{SERVICE_NAME} {VERSION} (Milestone 0 skeleton)")
}
