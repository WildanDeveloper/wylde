//! /proc readers. No dependencies, no guessing: a field that cannot be read is
//! reported as missing rather than invented.

use std::fs;

/// A single number from /proc, with the unit it was measured in.
#[derive(Debug, Clone, Copy)]
pub struct Reading {
    pub value: f64,
    pub unit: &'static str,
}

impl Reading {
    pub fn bytes(value: f64) -> Self {
        Reading { value, unit: "B" }
    }
    pub fn kib(value: f64) -> Self {
        Reading { value, unit: "KiB" }
    }
    pub fn ms(value: f64) -> Self {
        Reading { value, unit: "ms" }
    }
    pub fn hz(value: f64) -> Self {
        Reading { value, unit: "Hz" }
    }
}

pub fn read_trimmed(path: &str) -> Option<String> {
    fs::read_to_string(path)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

/// Parse `key:  value unit` lines from /proc files.
pub fn read_key_values(path: &str, wanted: &[&str]) -> Vec<(String, f64)> {
    let Some(text) = fs::read_to_string(path).ok() else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for line in text.lines() {
        let Some((key, rest)) = line.split_once(':') else {
            continue;
        };
        let key = key.trim();
        if !wanted.contains(&key) {
            continue;
        }
        let first = rest.split_whitespace().next().unwrap_or("");
        if let Ok(value) = first.parse::<f64>() {
            out.push((key.to_string(), value));
        }
    }
    out
}

pub fn value_of(pairs: &[(String, f64)], key: &str) -> Option<f64> {
    pairs
        .iter()
        .find(|(k, _)| k == key)
        .map(|(_, v)| *v)
}

/// Total physical memory in kibibytes.
pub fn mem_total_kib() -> Option<f64> {
    let pairs = read_key_values("/proc/meminfo", &["MemTotal", "MemFree", "MemAvailable", "Buffers", "Cached", "SwapTotal", "SwapFree"]);
    value_of(&pairs, "MemTotal")
}

pub fn cpu_count() -> usize {
    std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(1)
}

/// System uptime in seconds, from /proc/uptime (first field).
pub fn uptime_seconds() -> Option<f64> {
    let text = fs::read_to_string("/proc/uptime").ok()?;
    text.split_whitespace().next()?.parse::<f64>().ok()
}

/// Kernel command line, for the report header.
pub fn kernel_cmdline() -> Option<String> {
    read_trimmed("/proc/cmdline")
}

/// Distribution version string written by the installer.
pub fn version() -> Option<String> {
    read_trimmed("/etc/wylde-version")
}

/// Mount points that are tmpfs, i.e. RAM the system spends on files.
pub fn tmpfs_mounts() -> Vec<(String, String)> {
    let Some(text) = fs::read_to_string("/proc/mounts").ok() else {
        return Vec::new();
    };
    text.lines()
        .filter_map(|line| {
            let mut parts = line.split_whitespace();
            let _device = parts.next()?;
            let mount = parts.next()?.to_string();
            let fstype = parts.next()?.to_string();
            if fstype == "tmpfs" || fstype == "ramfs" {
                Some((mount, fstype))
            } else {
                None
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn meminfo_has_total() {
        // on any Linux this must succeed; it is the field the report needs
        assert!(mem_total_kib().is_some_and(|v| v > 0.0));
    }

    #[test]
    fn cpu_count_at_least_one() {
        assert!(cpu_count() >= 1);
    }

    #[test]
    fn uptime_is_positive() {
        assert!(uptime_seconds().is_some_and(|v| v > 0.0));
    }

    #[test]
    fn tmpfs_listing_parses() {
        // /dev/shm and friends are tmpfs; must not panic on any content
        let _ = tmpfs_mounts();
    }
}
