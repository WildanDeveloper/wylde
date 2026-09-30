//! Pkgfile parsing.
//!
//! A Pkgfile is a plain Bash file that `wld` reads for metadata and executes
//! for building. The format is intentionally boring: shell assignments plus a
//! `build()` function.
//!
//! ```bash
//! name=wget
//! version=1.25.0
//! source=https://ftp.gnu.org/gnu/wget/wget-$version.tar.gz
//! build() {
//!     ./configure --prefix=/usr
//!     make
//!     make DESTDIR=$PKG install
//! }
//! ```

use std::collections::BTreeMap;
use std::fmt;
use std::path::Path;

#[derive(Debug)]
pub enum PkgfileError {
    Io(std::io::Error),
    Malformed(String),
}

impl fmt::Display for PkgfileError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PkgfileError::Io(e) => write!(f, "{}", e),
            PkgfileError::Malformed(m) => write!(f, "malformed Pkgfile: {}", m),
        }
    }
}

impl From<std::io::Error> for PkgfileError {
    fn from(e: std::io::Error) -> Self {
        PkgfileError::Io(e)
    }
}

/// One parsed Pkgfile: its variables and the body of `build()`.
#[derive(Debug, Clone)]
pub struct Pkgfile {
    /// Every `key=value` assignment, in file order.
    pub vars: BTreeMap<String, String>,
    /// The raw text of `build()`.
    pub build: String,
}

impl Pkgfile {
    /// Parse a Pkgfile from disk.
    pub fn load(path: &Path) -> Result<Self, PkgfileError> {
        let text = std::fs::read_to_string(path)?;
        Self::parse(&text)
    }

    /// Parse Pkgfile text.
    pub fn parse(text: &str) -> Result<Self, PkgfileError> {
        let mut vars = BTreeMap::new();
        let mut build = String::new();
        let mut in_build = false;
        let mut depth: i64 = 0;

        for raw in text.lines() {
            let line = raw.trim_end();

            if in_build {
                let delta = brace_delta(line);
                // when this line closes the function, its final brace belongs to
                // the wrapper, not to the build body
                let closing = if depth + delta <= 0 { (1 - (depth + delta)) as usize } else { 0 };
                let mut text = line.to_string();
                for _ in 0..closing {
                    if text.trim_end().ends_with('}') {
                        let trimmed = text.trim_end().len() - 1;
                        text.truncate(trimmed);
                    }
                }
                build.push_str(&text);
                build.push('\n');
                depth += delta;
                if depth <= 0 {
                    in_build = false;
                }
                continue;
            }

            let trimmed = line.trim_start();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                continue;
            }

            if let Some(rest) = trimmed.strip_prefix("build()") {
                let rest = rest.trim();
                if !rest.starts_with('{') {
                    return Err(PkgfileError::Malformed(
                        "build() must be followed by a brace".into(),
                    ));
                }
                // A body may open and close on the same line: `build() { :; }`
                let opened_at = rest.find('{').unwrap_or(0);
                let closed_at = rest.rfind('}');
                match closed_at {
                    Some(close) if close > opened_at => {
                        build.push_str(&rest[opened_at + 1..close]);
                        build.push('\n');
                    }
                    _ => {
                        in_build = true;
                        depth = brace_delta(&rest[opened_at..]);
                    }
                }
                continue;
            }

            if let Some((key, value)) = trimmed.split_once('=') {
                let key = key.trim();
                // `checksum(<url>)=...` is a legitimate key; anything else must
                // be a plain identifier, otherwise this is a command, not metadata
                let plain = !key.is_empty()
                    && key.chars().all(|c| c.is_ascii_alphanumeric() || c == '_');
                let checksum_key = key.starts_with("checksum(") && key.ends_with(')');
                if !plain && !checksum_key {
                    continue;
                }
                vars.insert(key.to_string(), unquote(value.trim()));
            }
        }

        if build.trim().is_empty() {
            return Err(PkgfileError::Malformed("no build() function".into()));
        }
        if !vars.contains_key("name") {
            return Err(PkgfileError::malformed_no_name());
        }
        Ok(Pkgfile { vars, build })
    }

    pub fn name(&self) -> &str {
        self.vars.get("name").map(String::as_str).unwrap_or("unknown")
    }

    pub fn version(&self) -> &str {
        self.vars
            .get("version")
            .map(String::as_str)
            .unwrap_or("unknown")
    }

    /// Fetchable sources, in declaration order. `source` may be a single URL
    /// or a space/newline separated list.
    pub fn sources(&self) -> Vec<String> {
        self.vars
            .get("source")
            .map(|s| s.split_whitespace().map(str::to_string).collect())
            .unwrap_or_default()
    }

    pub fn checksum(&self, url: &str) -> Option<&str> {
        self.vars
            .get(&format!("checksum({})", url))
            .or_else(|| self.vars.get("checksum"))
            .map(String::as_str)
    }
}

// Small helper so the error enum stays readable above.
impl PkgfileError {
    fn malformed_no_name() -> Self {
        PkgfileError::Malformed("missing name=".into())
    }
}

/// Net brace balance of a line: `+1` per unquoted `{`, `-1` per `}`.
fn brace_delta(line: &str) -> i64 {
    let mut depth = 0i64;
    let mut in_single = false;
    let mut in_double = false;
    let mut prev = '\0';

    for c in line.chars() {
        match c {
            '\'' if !in_double => in_single = !in_single,
            '"' if !in_single => in_double = !in_double,
            '{' if !in_single && !in_double => depth += 1,
            '}' if !in_single && !in_double => depth -= 1,
            '\\' => {}
            _ => {}
        }
        if prev != '\\' && c == '#' && !in_single && !in_double {
            break;
        }
        prev = c;
    }

    depth
}

fn unquote(value: &str) -> String {
    let bytes = value.as_bytes();
    if bytes.len() >= 2 {
        let first = bytes[0];
        let last = bytes[bytes.len() - 1];
        if (first == b'"' && last == b'"') || (first == b'\'' && last == b'\'') {
            return value[1..value.len() - 1].to_string();
        }
    }
    value.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"
# a comment
name=wget
version=1.25.0
source="https://ftp.gnu.org/gnu/wget/wget-$version.tar.gz"
checksum(https://ftp.gnu.org/gnu/wget/wget-$version.tar.gz)=abc123

build() {
    ./configure --prefix=/usr
    if [ -n "$PKG" ]; then
        make DESTDIR="$PKG" install
    fi
}
"#;

    #[test]
    fn parses_metadata() {
        let pkg = Pkgfile::parse(SAMPLE).unwrap();
        assert_eq!(pkg.name(), "wget");
        assert_eq!(pkg.version(), "1.25.0");
        assert_eq!(pkg.sources().len(), 1);
        assert_eq!(
            pkg.checksum("https://ftp.gnu.org/gnu/wget/wget-$version.tar.gz"),
            Some("abc123")
        );
    }

    #[test]
    fn keeps_nested_braces_in_build() {
        let pkg = Pkgfile::parse(SAMPLE).unwrap();
        // inner braces (the if block) are kept...
        assert!(pkg.build.contains("if [ -n"));
        // ...but the function's own closing brace is not part of the body
        assert!(!pkg.build.trim_end().ends_with('}'));
        assert!(pkg.build.trim_end().ends_with("fi"));
    }

    #[test]
    fn single_line_build_body() {
        let pkg = Pkgfile::parse("name=x\nbuild() { make install; }\n").unwrap();
        assert_eq!(pkg.build.trim(), "make install;");
    }

    #[test]
    fn rejects_missing_name() {
        let err = Pkgfile::parse("build() {\n make\n}\n").unwrap_err();
        assert!(err.to_string().contains("name="));
    }

    #[test]
    fn rejects_missing_build() {
        assert!(Pkgfile::parse("name=x\n").is_err());
    }

    #[test]
    fn unquotes_values() {
        let pkg = Pkgfile::parse("name='quoted'\nbuild() { :; }\n").unwrap();
        assert_eq!(pkg.name(), "quoted");
    }
}
