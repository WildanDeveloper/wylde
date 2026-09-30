//! Report formatting: boot time, memory, and suggestions.

use crate::proc;

pub struct System {
    pub uptime_seconds: Option<f64>,
    pub memory_total_kib: Option<f64>,
    pub memory_available_kib: Option<f64>,
    pub memory_used_kib: Option<f64>,
    pub swap_total_kib: Option<f64>,
    pub swap_used_kib: Option<f64>,
    pub cpus: usize,
    pub kernel: Option<String>,
    pub version: Option<String>,
    pub tmpfs: Vec<(String, String)>,
}

impl System {
    pub fn gather() -> Self {
        let meminfo = proc::read_key_values(
            "/proc/meminfo",
            &["MemTotal", "MemAvailable", "SwapTotal", "SwapFree"],
        );
        let total = proc::value_of(&meminfo, "MemTotal");
        let available = proc::value_of(&meminfo, "MemAvailable");
        let swap_total = proc::value_of(&meminfo, "SwapTotal");
        let swap_free = proc::value_of(&meminfo, "SwapFree");
        System {
            uptime_seconds: proc::uptime_seconds(),
            memory_total_kib: total,
            memory_available_kib: available,
            memory_used_kib: total.zip(available).map(|(t, a)| t - a),
            swap_total_kib: swap_total,
            swap_used_kib: swap_total.zip(swap_free).map(|(t, f)| t - f),
            cpus: proc::cpu_count(),
            kernel: proc::kernel_cmdline(),
            version: proc::version(),
            tmpfs: proc::tmpfs_mounts(),
        }
    }

    fn memory_used_fraction(&self) -> Option<f64> {
        match (self.memory_used_kib, self.memory_total_kib) {
            (Some(used), Some(total)) if total > 0.0 => Some(used / total),
            _ => None,
        }
    }
}

pub fn human_bytes(kib: f64) -> String {
    let mib = kib / 1024.0;
    if mib >= 1024.0 {
        format!("{:.2} GiB", mib / 1024.0)
    } else {
        format!("{:.1} MiB", mib)
    }
}

pub fn boot_report(system: &System) -> String {
    let mut out = String::new();
    out.push_str("boot\n----\n");
    if let Some(version) = &system.version {
        out.push_str(&format!("  system:   Wylde {}\n", version));
    }
    if let Some(cmdline) = &system.kernel {
        out.push_str(&format!("  kernel:   {}\n", cmdline));
    }
    out.push_str(&format!("  cpus:     {}\n", system.cpus));
    match system.uptime_seconds {
        Some(seconds) => out.push_str(&format!("  uptime:   {:.1} s\n", seconds)),
        None => out.push_str("  uptime:   unavailable (/proc/uptime not readable)\n"),
    }
    out.push('\n');
    out
}

pub fn memory_report(system: &System) -> String {
    let mut out = String::new();
    out.push_str("memory\n------\n");
    match (system.memory_total_kib, system.memory_used_kib, system.memory_available_kib) {
        (Some(total), Some(used), Some(available)) => {
            let percent = used / total * 100.0;
            out.push_str(&format!(
                "  total:     {}  ({:.0}% used, {} available)\n",
                human_bytes(total),
                percent,
                human_bytes(available)
            ));
        }
        _ => out.push_str("  /proc/meminfo is not readable\n"),
    }
    if let (Some(total), Some(used)) = (system.swap_total_kib, system.swap_used_kib) {
        if total > 0.0 {
            out.push_str(&format!(
                "  swap:      {} of {} used\n",
                human_bytes(used),
                human_bytes(total)
            ));
        } else {
            out.push_str("  swap:      none configured\n");
        }
    }
    out.push('\n');
    out
}

/// Suggestions are derived from measurements, never from guesses about the host.
pub fn tips(system: &System) -> String {
    let mut out = String::new();
    out.push_str("suggestions\n-----------\n");
    let mut count = 0;

    if let Some(fraction) = system.memory_used_fraction() {
        if fraction > 0.25 {
            out.push_str(&format!(
                "  memory use is {:.0}% at idle; `wylde-doctor services` lists what is running\n",
                fraction * 100.0
            ));
            count += 1;
        }
    }

    if system.cpus > 8 {
        out.push_str("  more than 8 CPUs: services that scale with CPU count may dominate startup\n");
        count += 1;
    }

    let big_tmpfs: Vec<&(String, String)> = system
        .tmpfs
        .iter()
        .filter(|(mount, _)| mount.starts_with("/run") || mount == "/dev/shm")
        .collect();
    if big_tmpfs.len() > 2 {
        out.push_str("  several tmpfs mounts under /run: check for caches that outlive their purpose\n");
        count += 1;
    }

    if system.swap_total_kib.unwrap_or(0.0) > 0.0 {
        out.push_str("  swap is configured: for a CLI system, 4 GB of swap is usually enough headroom\n");
        count += 1;
    }

    if count == 0 {
        out.push_str("  nothing to suggest: this system looks lean\n");
    }
    out.push('\n');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn human_bytes_scales() {
        assert_eq!(human_bytes(512.0), "0.5 MiB");
        assert_eq!(human_bytes(1024.0), "1.0 MiB");
        assert_eq!(human_bytes(1024.0 * 1024.0), "1.00 GiB");
    }

    #[test]
    fn report_sections_always_produce_output() {
        let system = System::gather();
        assert!(boot_report(&system).starts_with("boot"));
        assert!(memory_report(&system).starts_with("memory"));
        assert!(tips(&system).contains("suggestions"));
    }

    #[test]
    fn a_clean_system_gets_a_clean_verdict() {
        let system = System {
            uptime_seconds: Some(1.0),
            memory_total_kib: Some(8.0 * 1024.0 * 1024.0),
            memory_available_kib: Some(7.0 * 1024.0 * 1024.0),
            memory_used_kib: Some(1024.0 * 1024.0),
            swap_total_kib: Some(0.0),
            swap_used_kib: Some(0.0),
            cpus: 4,
            kernel: None,
            version: None,
            tmpfs: vec![],
        };
        assert!(tips(&system).contains("nothing to suggest"));
    }
}
