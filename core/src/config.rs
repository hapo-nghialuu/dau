//! User / shipped configuration (TOML) and per-app typing strategy lookup.

use crate::engine::Method;
use std::collections::HashMap;
use std::path::Path;

/// Per-app typing strategy for the IME bridge.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Strategy {
    Preedit,
    CommitAtom,
    Passthrough,
}

/// Parsed configuration (partial fields remain `None` / empty when unset).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Config {
    pub method: Option<Method>,
    pub enabled: Option<bool>,
    pub auto_capitalize: Option<bool>,
    pub auto_restore: Option<bool>,
    pub shortcuts: Vec<(String, String)>,
    pub apps: HashMap<String, Strategy>,
}

impl Config {
    /// Parse from a TOML string. Syntax errors return `Err` with a description (never panics).
    pub fn from_toml_str(s: &str) -> Result<Config, String> {
        let table: toml::Table = s.parse().map_err(|e: toml::de::Error| e.to_string())?;
        Ok(Self::from_table(&table))
    }

    /// Read a file. Missing file → `Ok(Config::default())` (not an error).
    pub fn from_file(path: &Path) -> Result<Config, String> {
        match std::fs::read_to_string(path) {
            Ok(contents) => Self::from_toml_str(&contents),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Config::default()),
            Err(e) => Err(format!("read {}: {e}", path.display())),
        }
    }

    /// Merge: `self` is base (shipped), `other` (user) overrides when set.
    ///
    /// - Scalar options: user `Some` wins; `None` keeps base.
    /// - `apps`: union, user wins on key conflict.
    /// - `shortcuts`: user replaces entirely if non-empty; else keep base.
    pub fn merge(self, other: Config) -> Config {
        Config {
            method: other.method.or(self.method),
            enabled: other.enabled.or(self.enabled),
            auto_capitalize: other.auto_capitalize.or(self.auto_capitalize),
            auto_restore: other.auto_restore.or(self.auto_restore),
            shortcuts: if other.shortcuts.is_empty() {
                self.shortcuts
            } else {
                other.shortcuts
            },
            apps: {
                let mut apps = self.apps;
                for (k, v) in other.apps {
                    apps.insert(k, v);
                }
                apps
            },
        }
    }

    /// Look up strategy for `app_id` after merge; missing → `None`.
    pub fn strategy_for(&self, app_id: &str) -> Option<Strategy> {
        self.apps.get(app_id).copied()
    }

    fn from_table(table: &toml::Table) -> Config {
        let mut cfg = Config::default();

        if let Some(v) = table.get("method").and_then(|v| v.as_str()) {
            cfg.method = parse_method(v);
        }
        if let Some(v) = table.get("enabled").and_then(|v| v.as_bool()) {
            cfg.enabled = Some(v);
        }
        if let Some(v) = table.get("auto_capitalize").and_then(|v| v.as_bool()) {
            cfg.auto_capitalize = Some(v);
        }
        if let Some(v) = table.get("auto_restore").and_then(|v| v.as_bool()) {
            cfg.auto_restore = Some(v);
        }

        if let Some(shortcuts) = table.get("shortcuts").and_then(|v| v.as_table()) {
            for (k, v) in shortcuts {
                if let Some(val) = v.as_str() {
                    cfg.shortcuts.push((k.clone(), val.to_owned()));
                }
            }
        }

        if let Some(apps) = table.get("apps").and_then(|v| v.as_table()) {
            for (k, v) in apps {
                if let Some(s) = v.as_str() {
                    if let Some(strategy) = parse_strategy(s) {
                        cfg.apps.insert(k.clone(), strategy);
                    }
                    // Unknown strategy → skip (treat as undeclared).
                }
            }
        }

        cfg
    }
}

fn parse_method(s: &str) -> Option<Method> {
    match s.trim().to_ascii_lowercase().as_str() {
        "telex" => Some(Method::Telex),
        "vni" => Some(Method::Vni),
        _ => None,
    }
}

fn parse_strategy(s: &str) -> Option<Strategy> {
    match s.trim() {
        "preedit" => Some(Strategy::Preedit),
        "commit-atom" => Some(Strategy::CommitAtom),
        "passthrough" => Some(Strategy::Passthrough),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    const SAMPLE: &str = r#"
method = "telex"
enabled = true
auto_capitalize = true
auto_restore = true

[shortcuts]
vn = "Việt Nam"
ko = "không"

[apps]
"org.wezfurlong.wezterm" = "preedit"
"Alacritty" = "commit-atom"
"code" = "preedit"
"#;

    #[test]
    fn from_toml_str_parses_sample_schema() {
        let cfg = Config::from_toml_str(SAMPLE).expect("parse sample");
        assert_eq!(cfg.method, Some(Method::Telex));
        assert_eq!(cfg.enabled, Some(true));
        assert_eq!(cfg.auto_capitalize, Some(true));
        assert_eq!(cfg.auto_restore, Some(true));
        assert!(cfg
            .shortcuts
            .iter()
            .any(|(k, v)| k == "vn" && v == "Việt Nam"));
        assert_eq!(
            cfg.apps.get("Alacritty").copied(),
            Some(Strategy::CommitAtom)
        );
    }

    #[test]
    fn merge_user_overrides_apps() {
        let mut base = Config::default();
        base.apps.insert("A".into(), Strategy::Preedit);

        let mut user = Config::default();
        user.apps.insert("A".into(), Strategy::Passthrough);
        user.apps.insert("B".into(), Strategy::Preedit);

        let merged = base.merge(user);
        assert_eq!(merged.apps.get("A").copied(), Some(Strategy::Passthrough));
        assert_eq!(merged.apps.get("B").copied(), Some(Strategy::Preedit));
    }

    #[test]
    fn strategy_for_known_and_unknown() {
        let cfg = Config::from_toml_str(SAMPLE).unwrap();
        assert_eq!(
            cfg.strategy_for("org.wezfurlong.wezterm"),
            Some(Strategy::Preedit)
        );
        assert_eq!(cfg.strategy_for("unknown-app"), None);
    }

    #[test]
    fn from_file_missing_returns_default() {
        let path = PathBuf::from("/khong/ton/tai");
        let cfg = Config::from_file(&path).expect("missing file is ok");
        assert_eq!(cfg, Config::default());
    }

    #[test]
    fn invalid_toml_returns_err_no_panic() {
        let err = Config::from_toml_str("method = [unterminated").expect_err("bad toml");
        assert!(!err.is_empty());
    }

    #[test]
    fn unknown_strategy_skipped() {
        let cfg = Config::from_toml_str(
            r#"
[apps]
"foo" = "weird-mode"
"bar" = "preedit"
"#,
        )
        .unwrap();
        assert!(!cfg.apps.contains_key("foo"));
        assert_eq!(cfg.apps.get("bar").copied(), Some(Strategy::Preedit));
    }

    #[test]
    fn merge_shortcuts_user_nonempty_replaces() {
        let base = Config {
            shortcuts: vec![("a".into(), "A".into())],
            ..Config::default()
        };
        let user = Config {
            shortcuts: vec![("b".into(), "B".into())],
            ..Config::default()
        };
        let m = base.merge(user);
        assert_eq!(m.shortcuts, vec![("b".into(), "B".into())]);
    }

    #[test]
    fn merge_shortcuts_user_empty_keeps_base() {
        let base = Config {
            shortcuts: vec![("a".into(), "A".into())],
            ..Config::default()
        };
        let user = Config::default();
        let m = base.merge(user);
        assert_eq!(m.shortcuts, vec![("a".into(), "A".into())]);
    }
}
