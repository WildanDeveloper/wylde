//! Port tree handling and the build driver.
//!
//! A port is a directory under `ports/<category>/<name>/Pkgfile`. `wld` reads
//! the Pkgfile, fetches the sources, verifies checksums, and runs `build()` in
//! a scratch directory with `$PKG` pointing at a staging root. Nothing is
//! installed until the build finishes, and the file list is captured from the
//! staging root afterwards — that is the entire uninstall mechanism.

use std::collections::BTreeMap;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::db::{Database, Package};
use crate::pkgfile::Pkgfile;

#[derive(Debug)]
pub struct PortEntry {
    pub path: PathBuf,
    pub category: String,
}

pub struct PortTree {
    root: PathBuf,
}

impl PortTree {
    /// Locate the port tree: $WLD_ROOT/ports, or a `ports/` directory next to
    /// the source checkout (development mode).
    pub fn open(db: &Database) -> Result<Self, String> {
        let installed = db.ports_dir();
        if installed.is_dir() {
            return Ok(PortTree { root: installed });
        }
        // development mode: a ports/ tree next to the binary, two levels up
        // (wld/target/release/wld -> repo root), or in the current directory
        if let Ok(exe) = std::env::current_exe() {
            let mut dir = exe.parent().map(Path::to_path_buf);
            for _ in 0..4 {
                let Some(d) = dir else { break };
                let candidate = d.join("ports");
                if candidate.is_dir() {
                    return Ok(PortTree { root: candidate });
                }
                dir = d.parent().map(Path::to_path_buf);
            }
        }
        let cwd = PathBuf::from("ports");
        if cwd.is_dir() {
            return Ok(PortTree { root: cwd });
        }
        Ok(PortTree { root: installed })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Every port, sorted by path.
    pub fn entries(&self) -> Result<Vec<PortEntry>, String> {
        let mut out = Vec::new();
        if !self.root.is_dir() {
            return Ok(out);
        }
        for category in fs::read_dir(&self.root).map_err(|e| e.to_string())? {
            let category = category.map_err(|e| e.to_string())?;
            if !category.path().is_dir() {
                continue;
            }
            let category_name = category.file_name().to_string_lossy().to_string();
            for port in fs::read_dir(category.path()).map_err(|e| e.to_string())? {
                let port = port.map_err(|e| e.to_string())?;
                if port.path().join("Pkgfile").is_file() {
                    out.push(PortEntry {
                        path: port.path(),
                        category: category_name.clone(),
                    });
                }
            }
        }
        out.sort_by(|a, b| a.path.cmp(&b.path));
        Ok(out)
    }

    pub fn find(&self, name: &str) -> Result<Option<PortEntry>, String> {
        for entry in self.entries()? {
            let pkg = self.pkgfile(&entry.path)?;
            if pkg.name() == name {
                return Ok(Some(entry));
            }
        }
        Ok(None)
    }

    pub fn pkgfile(&self, dir: &Path) -> Result<Pkgfile, String> {
        Pkgfile::load(&dir.join("Pkgfile")).map_err(|e| e.to_string())
    }

    /// A printable tree of the port collection.
    pub fn tree(&self) -> Result<String, String> {
        let mut out = String::new();
        let mut by_category: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for entry in self.entries()? {
            let pkg = self.pkgfile(&entry.path)?;
            by_category
                .entry(entry.category.clone())
                .or_default()
                .push(pkg.name().to_string());
        }
        for (category, names) in by_category {
            out.push_str(&format!("{}\n", category));
            for name in names {
                out.push_str(&format!("  {}\n", name));
            }
        }
        Ok(out)
    }

    /// Build a port. Returns the list of files that a `make DESTDIR=$PKG
    /// install` style step staged.
    pub fn build(
        &self,
        pkgfile: &Pkgfile,
        _port_dir: &Path,
        db: &Database,
    ) -> Result<Build, String> {
        let work = db.build_dir().join(pkgfile.name());
        if work.exists() {
            let _ = fs::remove_dir_all(&work);
        }
        fs::create_dir_all(&work).map_err(|e| e.to_string())?;

        // fetch sources
        let src_dir = db.root().join("sources");
        fs::create_dir_all(&src_dir).map_err(|e| e.to_string())?;
        for url in pkgfile.sources() {
            let url = expand(&url, pkgfile);
            let file = src_dir.join(cache_name(pkgfile, &url));
            if !file.exists() {
                println!("==> fetching {}", url);
                fetch(&url, &file)?;
            }
            if let Some(expected) = pkgfile.checksum(&url) {
                if expected != "-" {
                    println!("==> verifying {}", file.display());
                    verify_checksum(&file, expected)?;
                }
            }
        }

        // patches: downloaded and verified next to the build, so build() can
        // refer to them by filename
        for url in pkgfile.patches() {
            let url = expand(&url, pkgfile);
            let file = work.join(url.rsplit('/').next().unwrap_or("patch"));
            if !file.exists() {
                println!("==> fetching patch {}", url);
                fetch(&url, &file)?;
            }
            if let Some(expected) = pkgfile.checksum(&url) {
                if expected != "-" {
                    verify_checksum(&file, expected)?;
                }
            }
        }

        // unpack: every source tarball lands next to the scratch build
        for url in pkgfile.sources() {
            let url = expand(&url, pkgfile);
            let file = src_dir.join(cache_name(pkgfile, &url));
            if !file.exists() {
                continue;
            }
            let status = Command::new("tar")
                .arg("-xf")
                .arg(&file)
                .arg("-C")
                .arg(&work)
                .status()
                .map_err(|e| format!("cannot run tar: {}", e))?;
            if !status.success() {
                return Err(format!("cannot unpack {}", file.display()));
            }
        }

        // the source directory is whatever the tarball left behind
        let srcdir = single_dir(&work).unwrap_or_else(|| work.clone());
        let pkg_stage = work.join("pkg");
        fs::create_dir_all(&pkg_stage).map_err(|e| e.to_string())?;

        // run build() with the environment a Pkgfile expects
        let destdir = std::env::var("WLD_DESTDIR").unwrap_or_else(|_| "/".to_string());
        let script = pkgfile.build.clone();
        let full = format!(
            "set -e\nPKG='{}'\nDESTDIR='{}'\nSRCDIR='{}'\nPATCHDIR='{}'\ncd '{}'\n{}\n",
            pkg_stage.display(),
            destdir,
            srcdir.display(),
            work.display(),
            srcdir.display(),
            script
        );
        let script_path = work.join("build.sh");
        fs::write(&script_path, &full).map_err(|e| e.to_string())?;
        fs::set_permissions(&script_path, fs::Permissions::from_mode(0o755))
            .map_err(|e| e.to_string())?;

        let status = Command::new("bash")
            .arg(&script_path)
            .status()
            .map_err(|e| format!("cannot run bash: {}", e))?;
        if !status.success() {
            return Err(format!("build() failed for {}", pkgfile.name()));
        }

        let mut files = Vec::new();
        collect_files(&pkg_stage, &pkg_stage, &mut files)?;
        files.sort();
        Ok(Build { stage: pkg_stage, files })
    }

    /// Copy a staged tree into the destination root and return the paths that
    /// were actually written. This is the list `remove` later deletes, which is
    /// why nothing may be created outside the staging root before this point.
    pub fn install(build: &Build, destdir: &Path) -> Result<Vec<PathBuf>, String> {
        use std::os::unix::fs::MetadataExt;
        let mut installed = Vec::new();
        // staged path -> (inode, destination), so files that the build already
        // hardlinked together stay one copy after installation
        let mut by_inode: std::collections::HashMap<(u64, u64), (PathBuf, PathBuf)> =
            std::collections::HashMap::new();

        for relative in &build.files {
            let from = build.stage.join(relative);
            let to = destdir.join(relative);
            if let Some(parent) = to.parent() {
                fs::create_dir_all(parent).map_err(|e| e.to_string())?;
            }
            let meta = fs::symlink_metadata(&from).map_err(|e| e.to_string())?;
            if meta.file_type().is_symlink() {
                let target = fs::read_link(&from).map_err(|e| e.to_string())?;
                let _ = fs::remove_file(&to);
                std::os::unix::fs::symlink(target, &to).map_err(|e| e.to_string())?;
            } else if meta.is_dir() {
                fs::create_dir_all(&to).map_err(|e| e.to_string())?;
                fs::set_permissions(&to, meta.permissions()).map_err(|e| e.to_string())?;
            } else if let Some((_, original)) = by_inode.get(&(meta.dev(), meta.ino())) {
                let _ = fs::remove_file(&to);
                if fs::hard_link(original, &to).is_err() {
                    fs::copy(&from, &to).map_err(|e| e.to_string())?;
                }
            } else {
                fs::copy(&from, &to).map_err(|e| e.to_string())?;
                fs::set_permissions(&to, meta.permissions()).map_err(|e| e.to_string())?;
                by_inode.insert((meta.dev(), meta.ino()), (from.clone(), to.clone()));
            }
            installed.push(relative.clone());
        }
        Ok(installed)
    }
}

/// The result of a successful build: the staging root and its file list.
pub struct Build {
    pub stage: PathBuf,
    pub files: Vec<PathBuf>,
}

/// Where a source is cached: package name plus the last URL path component, so
/// two ports can never clobber each other's tarball.
fn cache_name(pkgfile: &Pkgfile, url: &str) -> String {
    let tail = url
        .split('?')
        .next()
        .unwrap_or(url)
        .rsplit('/')
        .next()
        .filter(|s| !s.is_empty())
        .unwrap_or("source");
    format!("{}-{}", pkgfile.name(), tail)
}

/// Fetch a URL with whatever downloader the system has. A distro built from
/// scratch has no curl on day one, so wget is tried too.
fn fetch(url: &str, dest: &Path) -> Result<(), String> {
    let attempts: [(&str, Vec<&str>); 2] = [
        ("curl", vec!["-fsSL", "-o"]),
        ("wget", vec!["-q", "-O"]),
    ];
    let ca = "/etc/ssl/certs/ca-certificates.crt";
    let mut last = String::new();
    for (program, args) in attempts {
        let mut command = Command::new(program);
        command.args(&args).arg(dest).arg(url);
        // wget and curl each look for the CA bundle in their own compiled-in
        // path; Wylde keeps it in one place and says so explicitly
        if Path::new(ca).exists() {
            command.env("SSL_CERT_FILE", ca);
            command.env("CURL_CA_BUNDLE", ca);
        }
        match command.status() {
            Ok(status) if status.success() => return Ok(()),
            Ok(_) => last = format!("{} failed", program),
            Err(e) => last = format!("{}: {}", program, e),
        }
    }
    Err(format!("cannot fetch {} ({})", url, last))
}

fn single_dir(dir: &Path) -> Option<PathBuf> {
    let mut entries: Vec<PathBuf> = fs::read_dir(dir)
        .ok()?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.is_dir())
        .collect();
    entries.sort();
    entries.into_iter().next()
}

fn collect_files(root: &Path, dir: &Path, out: &mut Vec<PathBuf>) -> Result<(), String> {
    for entry in fs::read_dir(dir).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();
        let meta = fs::symlink_metadata(&path).map_err(|e| e.to_string())?;
        if meta.is_dir() {
            collect_files(root, &path, out)?;
        } else {
            out.push(
                path.strip_prefix(root)
                    .map_err(|e| e.to_string())?
                    .to_path_buf(),
            );
        }
    }
    Ok(())
}

/// Expand `$var` references inside a Pkgfile value.
fn expand(value: &str, pkgfile: &Pkgfile) -> String {
    let mut out = String::new();
    let mut chars = value.chars().peekable();
    while let Some(c) = chars.next() {
        if c != '$' {
            out.push(c);
            continue;
        }
        if chars.peek() == Some(&'{') {
            chars.next();
            let mut name = String::new();
            for c in chars.by_ref() {
                if c == '}' {
                    break;
                }
                name.push(c);
            }
            out.push_str(&expand_var(&name, pkgfile));
        } else {
            let mut name = String::new();
            while let Some(&c) = chars.peek() {
                if c.is_ascii_alphanumeric() || c == '_' {
                    name.push(c);
                    chars.next();
                } else {
                    break;
                }
            }
            out.push_str(&expand_var(&name, pkgfile));
        }
    }
    out
}

fn expand_var(name: &str, pkgfile: &Pkgfile) -> String {
    match name {
        "name" => pkgfile.name().to_string(),
        "version" => pkgfile.version().to_string(),
        other => pkgfile.vars.get(other).cloned().unwrap_or_default(),
    }
}

fn verify_checksum(file: &Path, expected: &str) -> Result<(), String> {
    let output = Command::new("sha256sum")
        .arg(file)
        .output()
        .map_err(|e| format!("cannot run sha256sum: {}", e))?;
    if !output.status.success() {
        return Err(format!("cannot checksum {}", file.display()));
    }
    let actual = String::from_utf8_lossy(&output.stdout)
        .split_whitespace()
        .next()
        .unwrap_or("")
        .to_string();
    if actual != expected {
        return Err(format!(
            "checksum mismatch for {}: expected {}, got {}",
            file.display(),
            expected,
            actual
        ));
    }
    Ok(())
}

/// Placeholder so `Package` stays used in the public API of this module.
#[allow(dead_code)]
fn _package_type_marker(_: &Package) {}
