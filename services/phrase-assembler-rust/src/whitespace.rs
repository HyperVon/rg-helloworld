pub fn encode(input: &str) -> String {
    let mut output = String::new();
    for byte in input.bytes() {
        for i in (0..8).rev() {
            if (byte >> i) & 1 == 1 {
                output.push('\t');
            } else {
                output.push(' ');
            }
        }
        output.push('\n');
    }
    output
}

pub fn decode(input: &str) -> Result<String, &'static str> {
    let mut bytes = Vec::new();
    for line in input.lines() {
        if line.is_empty() {
            continue;
        }
        if line.len() != 8 {
            return Err("invalid whitespace line length");
        }
        let mut byte: u8 = 0;
        for (i, ch) in line.chars().enumerate() {
            match ch {
                ' ' => {}
                '\t' => byte |= 1 << (7 - i),
                _ => return Err("invalid whitespace character"),
            }
        }
        bytes.push(byte);
    }
    String::from_utf8(bytes).map_err(|_| "invalid utf-8")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_empty() {
        assert_eq!(encode(""), "");
    }

    #[test]
    fn encode_single_char() {
        let encoded = encode("A");
        let expected = " \t     \t\n";
        assert_eq!(encoded, expected);
    }

    #[test]
    fn encode_decode_roundtrip() {
        let cases = ["", "A", "Hi", "RGHW", "\n\t"];
        for case in cases.iter() {
            let encoded = encode(case);
            let decoded = decode(&encoded).unwrap();
            assert_eq!(decoded, *case, "roundtrip failed for {:?}", case);
        }
    }

    #[test]
    fn decode_invalid_length() {
        let result = decode(" 0100");
        assert!(result.is_err());
    }

    #[test]
    fn decode_invalid_character() {
        let result = decode("x0100000");
        assert!(result.is_err());
    }

    #[test]
    fn encode_deterministic() {
        let first = encode(" provenance ");
        let second = encode(" provenance ");
        assert_eq!(first, second);
    }

    #[test]
    fn decode_empty() {
        assert_eq!(decode("").unwrap(), "");
    }
}
