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
