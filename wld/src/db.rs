//! The installed-package database.
//!
//! Deliberately a flat file, not SQLite. One line per installed file, one file
//! per package, so that a broken package is a readable text file and can be
//! removed by hand.
//!
//! Layout:
//! ```text
//! /var/lib/wld/db/<name>-<version>.files   one absolute path per line
//! /var/lib/wld/db/<name>-<version>.info   key=value metadata
//! /var/lib/wld/ports                      the port tree root
//! /var/lib/wld/build                      scratch build root
//! ```

use std::fmt;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

#[derive(Debug)]
pub enum DbError {
    Io(std::io::Error),
    Corrupt(String),
}

impl fmt::Display for DbError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DbError::Io(e) => write!(f, "{}", e),
            DbError::Corrupt(m) => write!(f, "corrupt database: {}", m),
        }
    }
}

impl From<std::io::Error> for DbError {
    fn from(e: std::io::Error) -> Self {
        DbError::Io(e)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Package {
    pub name: String,
    pub version: String,
}

impl Package {
    pub fn key(&self) -> String {
        format!("{}-{}", self.name, self.version)
    }
}

#[derive(Debug, Clone, Default)]
pub struct PackageInfo {
    pub name: String,
    pub version: String,
    pub source: String,
    pub build_date: String,
    pub files: usize,
    pub size: u64,
}

pub struct Database {
    root: PathBuf,
}

impl Database {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Database { root: root.into() }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn db_dir(&self) -> PathBuf {
        self.root.join("db")
    }

    pub fn ports_dir(&self) -> PathBuf {
        self.root.join("ports")
    }

    pub fn build_dir(&self) -> PathBuf {
        self.root.join("build")
    }

    pub fn init(&self) -> Result<(), DbError> {
        for dir in [self.db_dir(), self.ports_dir(), self.build_dir()] {
            fs::create_dir_all(dir)?;
        }
        Ok(())
    }

    fn files_path(&self, pkg: &Package) -> PathBuf {
        self.db_dir().join(format!("{}.files", pkg.key()))
    }

    fn info_path(&self, pkg: &Package) -> PathBuf {
        self.db_dir().join(format!("{}.info", pkg.key()))
    }

    /// All installed packages, sorted by name.
    pub fn installed(&self) -> Result<Vec<Package>, DbError> {
        let mut out = Vec::new();
        let dir = self.db_dir();
        if !dir.exists() {
            return Ok(out);
        }
        for entry in fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("info") {
                continue;
            }
            let info = self.read_info(&path)?;
            out.push(Package {
                name: info.name,
                version: info.version,
            });
        }
        out.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(out)
    }

    pub fn find(&self, name: &str) -> Result<Option<Package>, DbError> {
        Ok(self
            .installed()?
            .into_iter()
            .find(|p| p.name == name))
    }

    fn read_info(&self, path: &Path) -> Result<PackageInfo, DbError> {
        let text = fs::read_to_string(path)?;
        let mut info = PackageInfo::default();
        for line in text.lines() {
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            match key {
                "name" => info.name = value.to_string(),
                "version" => info.version = value.to_string(),
                "source" => info.source = value.to_string(),
                "build_date" => info.build_date = value.to_string(),
                "files" => {
                    info.files = value.parse().unwrap_or(0);
                }
                "size" => {
                    info.size = value.parse().unwrap_or(0);
                }
                _ => {}
            }
        }
        if info.name.is_empty() {
            return Err(DbError::Corrupt(format!("{} has no name", path.display())));
        }
        Ok(info)
    }

    /// Read a package's file list.
    pub fn files(&self, pkg: &Package) -> Result<Vec<PathBuf>, DbError> {
        let path = self.files_path(pkg);
        if !path.exists() {
            return Ok(Vec::new());
        }
        let reader = BufReader::new(fs::File::open(path)?);
        let mut out = Vec::new();
        for line in reader.lines() {
            let line = line?;
            let trimmed = line.trim();
            if !trimmed.is_empty() {
                out.push(PathBuf::from(trimmed));
            }
        }
        Ok(out)
    }

    /// Record an installed package.
    pub fn register(
        &self,
        pkg: &Package,
        source: &str,
        files: &[PathBuf],
        size: u64,
    ) -> Result<(), DbError> {
        self.init()?;
        let mut list = fs::File::create(self.files_path(pkg))?;
        for file in files {
            writeln!(list, "{}", file.display())?;
        }
        let mut info = fs::File::create(self.info_path(pkg))?;
        writeln!(info, "name={}", pkg.name)?;
        writeln!(info, "version={}", pkg.version)?;
        writeln!(info, "source={}", source)?;
        writeln!(info, "build_date={}", build_date())?;
        writeln!(info, "files={}", files.len())?;
        writeln!(info, "size={}", size)?;
        Ok(())
    }

    /// Remove a package's database entries and return its file list.
    pub fn forget(&self, pkg: &Package) -> Result<Vec<PathBuf>, DbError> {
        let files = self.files(pkg)?;
        let _ = fs::remove_file(self.files_path(pkg));
        let _ = fs::remove_file(self.info_path(pkg));
        Ok(files)
    }
}

/// sha256 of a file, computed here so `wld` stays dependency-free.
pub fn sha256_of(path: &std::path::Path) -> String {
    let data = std::fs::read(path).unwrap_or_default();
    sha256(&data).iter().map(|b| format!("{:02x}", b)).collect()
}

/// SHA-256 (FIPS 180-4). Small enough to keep in-tree instead of pulling a crate.
pub fn sha256(data: &[u8]) -> [u8; 32] {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
        0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
        0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
        0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
        0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
        0x1f83d9ab, 0x5be0cd19,
    ];

    let mut message = data.to_vec();
    let bit_length = (data.len() as u64) * 8;
    message.push(0x80);
    while message.len() % 64 != 56 {
        message.push(0);
    }
    message.extend_from_slice(&bit_length.to_be_bytes());

    for chunk in message.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([
                chunk[i * 4],
                chunk[i * 4 + 1],
                chunk[i * 4 + 2],
                chunk[i * 4 + 3],
            ]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }

        let mut v = h;
        for i in 0..64 {
            let s1 = v[4].rotate_right(6) ^ v[4].rotate_right(11) ^ v[4].rotate_right(25);
            let ch = (v[4] & v[5]) ^ ((!v[4]) & v[6]);
            let temp1 = v[7]
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = v[0].rotate_right(2) ^ v[0].rotate_right(13) ^ v[0].rotate_right(22);
            let maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2]);
            let temp2 = s0.wrapping_add(maj);

            v[7] = v[6];
            v[6] = v[5];
            v[5] = v[4];
            v[4] = v[3].wrapping_add(temp1);
            v[3] = v[2];
            v[2] = v[1];
            v[1] = v[0];
            v[0] = temp1.wrapping_add(temp2);
        }
        for i in 0..8 {
            h[i] = h[i].wrapping_add(v[i]);
        }
    }

    let mut out = [0u8; 32];
    for i in 0..8 {
        out[i * 4..i * 4 + 4].copy_from_slice(&h[i].to_be_bytes());
    }
    out
}

/// Date the package was built, UTC, no external crates.
fn build_date() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    // days since epoch -> civil date (Howard Hinnant's algorithm)
    let days = (secs / 86_400) as i64;
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!("{:04}-{:02}-{:02}", y, m, d)
}

/// Total size in bytes of a list of paths (files only; symlinks count as 0).
///
/// Hardlinked files are counted once: `git` installs ~180 hardlinks to the
/// same binary, and adding each path separately would report gigabytes that do
/// not exist on disk.
pub fn total_size(files: &[PathBuf]) -> u64 {
    use std::os::unix::fs::MetadataExt;
    let mut seen: std::collections::HashSet<(u64, u64)> = std::collections::HashSet::new();
    let mut total = 0;
    for file in files {
        if let Ok(meta) = fs::symlink_metadata(file) {
            if meta.is_file() {
                if seen.insert((meta.dev(), meta.ino())) {
                    total += meta.len();
                }
            }
        }
    }
    total
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Minimal scratch directory: no external crates, removed on drop.
    struct TempDir(PathBuf);

    impl TempDir {
        fn new(tag: &str) -> Self {
            let pid = std::process::id();
            let path = std::env::temp_dir().join(format!("wld-test-{}-{}-{}", tag, pid, nanos()));
            fs::create_dir_all(&path).expect("create temp dir");
            TempDir(path)
        }
        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn nanos() -> u128 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.subsec_nanos() as u128)
            .unwrap_or(0)
    }

    fn tmp_db() -> (TempDir, Database) {
        let dir = TempDir::new("db");
        let db = Database::new(dir.path().join("wld"));
        db.init().unwrap();
        (dir, db)
    }

    #[test]
    fn register_and_list() {
        let (_d, db) = tmp_db();
        let pkg = Package {
            name: "wget".into(),
            version: "1.25.0".into(),
        };
        let files = vec![PathBuf::from("/usr/bin/wget"), PathBuf::from("/usr/share/doc/wget")];
        db.register(&pkg, "https://example/wget.tar.gz", &files, 4096).unwrap();

        let installed = db.installed().unwrap();
        assert_eq!(installed.len(), 1);
        assert_eq!(installed[0], pkg);
        assert_eq!(db.files(&pkg).unwrap().len(), 2);
        assert_eq!(db.find("wget").unwrap(), Some(pkg.clone()));
        assert_eq!(db.find("nothing").unwrap(), None);
    }

    #[test]
    fn forget_returns_files() {
        let (_d, db) = tmp_db();
        let pkg = Package {
            name: "curl".into(),
            version: "8.0".into(),
        };
        db.register(&pkg, "s", &[PathBuf::from("/usr/bin/curl")], 1).unwrap();
        let files = db.forget(&pkg).unwrap();
        assert_eq!(files.len(), 1);
        assert!(db.installed().unwrap().is_empty());
    }

    #[test]
    fn hardlinks_counted_once() {
        let (_d, db) = tmp_db();
        let a = _d.path().join("a");
        let b = _d.path().join("b");
        fs::write(&a, b"0123456789").unwrap();
        fs::hard_link(&a, &b).unwrap();
        let total = total_size(&[a.clone(), b.clone()]);
        assert_eq!(total, 10);
        let _ = db;
    }

    #[test]
    fn date_is_iso() {
        let d = build_date();
        assert_eq!(d.len(), 10);
        assert_eq!(&d[4..5], "-");
        assert!(d.chars().all(|c| c.is_ascii_digit() || c == '-'));
    }
}

#[cfg(test)]
mod sha_tests {
    use super::sha256;

    fn hex(bytes: [u8; 32]) -> String {
        bytes.iter().map(|b| format!("{:02x}", b)).collect()
    }

    #[test]
    fn known_vectors() {
        assert_eq!(
            hex(sha256(b"")),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            hex(sha256(b"abc")),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(
            hex(sha256(b"The quick brown fox jumps over the lazy dog")),
            "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
        );
    }
}
