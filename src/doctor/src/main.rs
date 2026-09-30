//! wylde-doctor — reports what a running Wylde system is doing, and suggests what
//! to switch off. Every number it prints comes from the kernel or /proc; nothing
//! is estimated, and nothing is changed without being asked.

mod proc;
mod report;
mod services;

use std::process::ExitCode;

const USAGE: &str = "\
wylde-doctor — report on a running Wylde system

USAGE:
    wylde-doctor              full report
    wylde-doctor boot         boot timing only
    wylde-doctor memory       memory only
    wylde-doctor services     running services only
    wylde-doctor tips         suggestions only
    wylde-doctor --help

The report is read-only. wylde-doctor never stops a service on its own.
";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.iter().any(|a| a == "-h" || a == "--help" || a == "help") {
        print!("{}", USAGE);
        return ExitCode::SUCCESS;
    }
    let only = args.first().map(String::as_str);

    let system = report::System::gather();
    let mut out = String::new();

    let want = |section: &str| only.is_none() || only == Some(section);

    if want("boot") {
        out.push_str(&report::boot_report(&system));
    }
    if want("memory") {
        out.push_str(&report::memory_report(&system));
    }
    if want("services") {
        out.push_str(&services::report(&system));
    }
    if want("tips") {
        out.push_str(&report::tips(&system));
    }

    print!("{}", out);
    ExitCode::SUCCESS
}
