//! Service inspection: what PID 1 was told to start, what is actually running,
//! and whether the two agree.

use crate::proc;
use crate::report::System;

/// One line of /etc/wylde/services, parsed.
#[derive(Debug, Clone)]
pub struct Service {
    pub name: String,
    pub command: String,
    pub oneshot: bool,
}

pub fn read_service_list(path: &str) -> Vec<Service> {
    let Ok(text) = std::fs::read_to_string(path) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for raw in text.lines() {
        let without_comment = raw.split('#').next().unwrap_or("");
        let line = without_comment.trim();
        if line.is_empty() {
            continue;
        }
        let (oneshot, rest) = match line.strip_prefix('!') {
            Some(rest) => (true, rest.trim()),
            None => (false, line),
        };
        let Some((name, command)) = rest.split_once(char::is_whitespace) else {
            continue;
        };
        out.push(Service {
            name: name.to_string(),
            command: command.trim().to_string(),
            oneshot,
        });
    }
    out
}

/// PIDs of processes whose parent is 1, with their command names.
pub fn running_children_of_init() -> Vec<(u32, String)> {
    let Ok(text) = std::fs::read_to_string("/proc/smaps_rollup") else {
        return Vec::new();
    };
    let _ = text; // not needed; kept for symmetry of error handling
    let mut out = Vec::new();
    let Ok(entries) = std::fs::read_dir("/proc") else {
        return out;
    };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        let Ok(pid) = name.parse::<u32>() else {
            continue;
        };
        let Some(stat) = proc::read_trimmed(&format!("/proc/{}/stat", pid)) else {
            continue;
        };
        // comm may contain spaces, so parse from the last ')' before the state
        let Some(close) = stat.rfind(')') else {
            continue;
        };
        let after = stat[close + 1..].trim();
        let mut fields = after.split_whitespace();
        let _state = fields.next();
        let _ppid = fields.next();
        let comm = proc::read_trimmed(&format!("/proc/{}/comm", pid)).unwrap_or_default();
        if _ppid == Some("1") && !comm.is_empty() {
            out.push((pid, comm));
        }
    }
    out.sort_by_key(|(pid, _)| *pid);
    out
}

pub fn report(system: &System) -> String {
    let mut out = String::new();
    out.push_str("services\n");
    out.push_str("--------\n");

    let list = read_service_list("/etc/wylde/services");
    if list.is_empty() {
        out.push_str("  no service list at /etc/wylde/services\n");
        return out;
    }

    let running = running_children_of_init();
    for service in &list {
        let marker = if service.oneshot {
            "once "
        } else {
        "     "
        };
        let alive = running
            .iter()
            .any(|(_, comm)| service.command.split_whitespace().next() == Some(comm.as_str()));
        let state = if alive { "running" } else { "not running" };
        out.push_str(&format!(
            "  {}{:<14} {}\n",
            marker, service.name, state
        ));
    }

    out.push_str(&format!(
        "\n  {} processes are children of PID 1\n",
        running.len()
    ));
    let _ = system;
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_a_service_list() {
        let text = "# comment\n!sysctl /sbin/sysctl --system\nsyslogd /usr/sbin/syslogd -F\n\nbrokenline\n";
        let dir = std::env::temp_dir().join(format!("wld-doc-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("services");
        std::fs::write(&path, text).unwrap();
        let services = read_service_list(path.to_str().unwrap());
        assert_eq!(services.len(), 2);
        assert!(services[0].oneshot);
        assert_eq!(services[0].name, "sysctl");
        assert_eq!(services[1].command, "/usr/sbin/syslogd -F");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn missing_file_is_not_an_error() {
        assert!(read_service_list("/nonexistent/wylde/services").is_empty());
    }
}
