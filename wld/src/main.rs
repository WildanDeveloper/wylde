//! wld — the Wylde package manager.
//!
//! Principles, same as the rest of the system: no runtime dependencies, no
//! hidden state, everything readable. The database is a flat file, ports are
//! plain Bash, and `wld info` can always explain what a package is.

mod db;
mod pkgfile;
mod ports;

use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

const USAGE: &str = "\
wld — Wylde package manager

USAGE:
    wld <command> [args]

COMMANDS:
    build <port>      Build a port from ports/ (no install)
    install <port>    Build and install a port
    remove <name>     Remove an installed package and its files
    list              List installed packages
    info <name>       Show details about a package
    search <term>     Search ports by name and description
    ports             List available ports
    tree              Show the port tree
    doctor            Report on the local wld installation
    sync              Fetch the package repository index
    upgrade <name>    Upgrade a package to the repository version

ENVIRONMENT:
    WLD_ROOT          database root (default /var/lib/wld)
    WLD_DESTDIR       install prefix used by build (default /)
";

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() || args[0] == "-h" || args[0] == "--help" || args[0] == "help" {
        print!("{}", USAGE);
        return ExitCode::SUCCESS;
    }

    let root = env::var("WLD_ROOT").unwrap_or_else(|_| "/var/lib/wld".to_string());
    let db = db::Database::new(&root);

    let result = match args[0].as_str() {
        "ports" => cmd_ports(&db),
        "search" => cmd_search(&db, args.get(1)),
        "tree" => cmd_tree(&db),
        "list" | "ls" => cmd_list(&db),
        "info" => cmd_info(&db, args.get(1)),
        "build" => cmd_build(&db, args.get(1), false),
        "install" | "add" => cmd_build(&db, args.get(1), true),
        "remove" | "rm" | "uninstall" => cmd_remove(&db, args.get(1)),
        "doctor" => cmd_doctor(&db),
        "sync" => cmd_sync(&db),
        "upgrade" => cmd_upgrade(&db, args.get(1)),
        other => Err(format!("unknown command '{}'\n\n{}", other, USAGE)),
    };

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("wld: {}", message);
            ExitCode::FAILURE
        }
    }
}

fn cmd_ports(db: &db::Database) -> Result<(), String> {
    let ports = ports::PortTree::open(db)?;
    let entries = ports.entries()?;
    if entries.is_empty() {
        println!("no ports found in {}", ports.root().display());
        return Ok(());
    }
    for entry in &entries {
        let pkg = ports.pkgfile(&entry.path)?;
        println!("{:<20} {}", pkg.name(), pkg.version());
    }
    Ok(())
}

fn cmd_search(db: &db::Database, term: Option<&String>) -> Result<(), String> {
    let needle = term.map(|s| s.to_lowercase()).unwrap_or_default();
    let ports = ports::PortTree::open(db)?;
    for entry in ports.entries()? {
        let pkg = ports.pkgfile(&entry.path)?;
        let haystack = format!(
            "{} {} {}",
            pkg.name().to_lowercase(),
            pkg.version(),
            pkg.vars.get("description").cloned().unwrap_or_default().to_lowercase()
        );
        if needle.is_empty() || haystack.contains(&needle) {
            let description = pkg.vars.get("description").cloned().unwrap_or_default();
            println!("{:<20} {:<12} {}", pkg.name(), pkg.version(), description);
        }
    }
    Ok(())
}

fn cmd_tree(db: &db::Database) -> Result<(), String> {
    let ports = ports::PortTree::open(db)?;
    print!("{}", ports.tree()?);
    Ok(())
}

fn cmd_list(db: &db::Database) -> Result<(), String> {
    let installed = db.installed().map_err(|e| e.to_string())?;
    if installed.is_empty() {
        println!("no packages installed");
        return Ok(());
    }
    println!("{:<24} {}", "NAME", "VERSION");
    for pkg in installed {
        println!("{:<24} {}", pkg.name, pkg.version);
    }
    Ok(())
}

fn cmd_info(db: &db::Database, name: Option<&String>) -> Result<(), String> {
    let name = need(name, "info")?;
    let pkg = db
        .find(name)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| format!("{} is not installed", name))?;
    let files = db.files(&pkg).map_err(|e| e.to_string())?;

    println!("name:         {}", pkg.name);
    println!("version:      {}", pkg.version);
    println!("files:        {}", files.len());
    println!(
        "size:         {}",
        human_size(db::total_size(&files))
    );
    if let Some(port) = ports::PortTree::open(db)?.find(&pkg.name)? {
        let pkgfile = ports::PortTree::open(db)?.pkgfile(&port.path)?;
        println!("port:         {}", port.path.display());
        println!("source:       {}", pkgfile.vars.get("source").cloned().unwrap_or_default());
        if let Some(deps) = pkgfile.vars.get("depends") {
            println!("depends:      {}", deps);
        }
    }
    Ok(())
}

fn cmd_build(db: &db::Database, name: Option<&String>, install: bool) -> Result<(), String> {
    let name = need(name, if install { "install" } else { "build" })?;
    let ports = ports::PortTree::open(db)?;
    let entry = ports
        .find(name)?
        .ok_or_else(|| format!("no port named '{}' (try 'wld ports')", name))?;
    let pkgfile = ports.pkgfile(&entry.path)?;

    println!("==> {} {} ({})", pkgfile.name(), pkgfile.version(), entry.category);
    println!("    {}", entry.path.display());

    let package = db::Package {
        name: pkgfile.name().to_string(),
        version: pkgfile.version().to_string(),
    };
    let built = ports::PortTree::build(&ports, &pkgfile, &entry.path, db)?;
    println!("==> built {} files", built.files.len());

    if !install {
        return Ok(());
    }

    let destdir = PathBuf::from(env::var("WLD_DESTDIR").unwrap_or_else(|_| "/".to_string()));
    let files = ports::PortTree::install(&built, &destdir)?;
    println!("==> installed into {}", destdir.display());

    let mut absolute = Vec::new();
    for file in &files {
        absolute.push(destdir.join(file));
    }
    let size = db::total_size(&absolute);
    db.register(&package, &pkgfile.vars.get("source").cloned().unwrap_or_default(), &absolute, size)
        .map_err(|e| e.to_string())?;
    println!("==> {} {} installed ({} files, {})", package.name, package.version, files.len(), human_size(size));
    Ok(())
}

fn cmd_remove(db: &db::Database, name: Option<&String>) -> Result<(), String> {
    let name = need(name, "remove")?;
    let pkg = db
        .find(name)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| format!("{} is not installed", name))?;
    let files = db.forget(&pkg).map_err(|e| e.to_string())?;

    let mut removed = 0;
    for file in files.iter().rev() {
        match std::fs::remove_file(file) {
            Ok(()) => removed += 1,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => eprintln!("wld: cannot remove {}: {}", file.display(), e),
        }
    }
    println!("removed {} {} ({} files)", pkg.name, pkg.version, removed);
    Ok(())
}

fn cmd_doctor(db: &db::Database) -> Result<(), String> {
    let ports = ports::PortTree::open(db)?;
    let installed = db.installed().map_err(|e| e.to_string())?;

    println!("wld root:   {}", db.root().display());
    println!("ports root: {}", ports.root().display());
    println!("installed:  {}", installed.len());
    println!("ports:      {}", ports.entries().map(|e| e.len()).unwrap_or(0));

    for dir in [db.db_dir().to_path_buf(), ports.root().to_path_buf(), db.build_dir()] {
        let status = if dir.exists() { "ok" } else { "missing" };
        println!("  {:<50} {}", dir.display(), status);
    }

    for bin in ["bash", "make", "gcc", "tar", "install"] {
        let found = std::env::var("PATH")
            .unwrap_or_default()
            .split(':')
            .any(|p| std::path::Path::new(p).join(bin).exists());
        println!("  tool {:<10} {}", bin, if found { "ok" } else { "missing" });
    }
    Ok(())
}

/// Repository base URL: WLD_REPO, or the file in the wld root, or the default.
fn repo_url(db: &db::Database) -> String {
    if let Ok(url) = env::var("WLD_REPO") {
        return url;
    }
    let file = db.root().join("repository");
    if let Ok(text) = std::fs::read_to_string(&file) {
        if let Some(url) = text.lines().find_map(|l| l.strip_prefix("url=")) {
            return url.trim().to_string();
        }
    }
    "https://wylde.github.io/wylde-repo".to_string()
}

fn cmd_sync(db: &db::Database) -> Result<(), String> {
    let url = repo_url(db);
    println!("repository: {}", url);
    let cache = db.root().join("repo");
    let entries = ports::fetch_index(&url, &cache)?;
    let installed = db.installed().map_err(|e| e.to_string())?;
    println!("{} packages in the repository\n", entries.len());
    println!("{:<22} {:<14} {}", "NAME", "VERSION", "STATE");
    for entry in &entries {
        let state = match installed.iter().find(|p| p.name == entry.name) {
            Some(current) if current.version == entry.version => "up to date",
            Some(_) => "update available",
            None => "not installed",
        };
        println!("{:<22} {:<14} {}", entry.name, entry.version, state);
    }
    Ok(())
}

fn cmd_upgrade(db: &db::Database, name: Option<&String>) -> Result<(), String> {
    let name = need(name, "upgrade")?;
    let url = repo_url(db);
    let cache = db.root().join("repo");
    let entries = ports::fetch_index(&url, &cache)?;
    let entry = entries
        .iter()
        .find(|e| e.name == *name)
        .ok_or_else(|| format!("{} is not in the repository", name))?;

    match db.find(name).map_err(|e| e.to_string())? {
        Some(current) if current.version == entry.version => {
            println!("{} {} is already current", name, entry.version);
            return Ok(());
        }
        Some(current) => println!("upgrading {} {} -> {}", name, current.version, entry.version),
        None => println!("installing {} {}", name, entry.version),
    }

    let archive = ports::fetch_package(&url, entry, &db.build_dir())?;
    println!("==> archive: {}", archive.display());
    println!("==> unpack into / and refresh the database with 'wld install <port>' when sources change");
    Ok(())
}

fn need<'a>(arg: Option<&'a String>, command: &str) -> Result<&'a String, String> {
    arg.ok_or_else(|| format!("'{}' needs an argument", command))
}

fn human_size(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["B", "KiB", "MiB", "GiB", "TiB"];
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1024.0 && unit + 1 < UNITS.len() {
        value /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{} {}", bytes, UNITS[0])
    } else {
        format!("{:.1} {}", value, UNITS[unit])
    }
}
