use std::{
  ffi::OsString,
  path::{Path, PathBuf},
  process::Command,
};

use tennis::Grid;

use crate::{
  error::{Error, Result},
  input::csv,
};

//
// SQLite loading
//

/// Export the selected sqlite table as CSV, then reuse the CSV loader.
pub fn load(path: &Path, selected_table: Option<&str>) -> Result<Grid> {
  let tables = list_tables(path)?;
  let table = choose_table(path, &tables, selected_table)?;
  let sql = format!("SELECT * FROM {};", quote_identifier(&table));
  let stdout = run(path, &["-batch", "-header", "-csv"], &sql)?;
  csv::load(&stdout, b',')
}

/// List user tables, excluding sqlite internals.
pub fn list_tables(path: &Path) -> Result<Vec<String>> {
  let sql = "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;";
  let stdout = run(path, &["-batch", "-noheader"], sql)?;
  let text = String::from_utf8_lossy(&stdout);
  Ok(text.lines().map(str::trim).filter(|line| !line.is_empty()).map(ToOwned::to_owned).collect())
}

/// Resolve --table or choose the largest table by storage size.
fn choose_table(path: &Path, tables: &[String], selected_table: Option<&str>) -> Result<String> {
  if tables.is_empty() {
    return Err(Error::SqliteNoTables);
  }
  if let Some(selected_table) = selected_table {
    return tables
      .iter()
      .find(|table| table.eq_ignore_ascii_case(selected_table))
      .cloned()
      .ok_or_else(|| Error::SqliteInvalidTable(selected_table.to_owned(), tables.to_vec()));
  }

  let sql = "SELECT name FROM (SELECT sm.name AS name, COALESCE(SUM(ds.pgsize), 0) AS total_size FROM sqlite_master AS sm LEFT JOIN dbstat AS ds ON ds.name = sm.name WHERE sm.type = 'table' AND sm.name NOT LIKE 'sqlite_%' GROUP BY sm.name) ORDER BY total_size DESC, name ASC LIMIT 1;";
  Ok(query_scalar(path, sql).unwrap_or_else(|_| tables[0].clone()))
}

/// Run a query expected to return one text value.
fn query_scalar(path: &Path, sql: &str) -> Result<String> {
  let stdout = run(path, &["-batch", "-noheader"], sql)?;
  let text = String::from_utf8_lossy(&stdout);
  let value = text.trim();
  if value.is_empty() { Err(Error::SqliteNoTables) } else { Ok(value.to_owned()) }
}

/// Run sqlite3 read-only with fixed argv and no shell.
fn run(path: &Path, args: &[&str], sql: &str) -> Result<Vec<u8>> {
  let mut command = Command::new("sqlite3");
  command.arg("-readonly").args(args).arg(path_arg(path)).arg(sql);

  let output = command.output().map_err(|err| match err.kind() {
    std::io::ErrorKind::NotFound => Error::SqliteCliMissing,
    _ => Error::SqliteCliFailed,
  })?;
  if !output.status.success() {
    return Err(Error::SqliteCliFailed);
  }
  Ok(output.stdout)
}

/// Prefix dash-starting relative paths so sqlite3 won't parse them as flags.
fn path_arg(path: &Path) -> OsString {
  if path.is_relative()
    && path.components().next().is_some_and(|component| component.as_os_str().to_string_lossy().starts_with('-'))
  {
    PathBuf::from(".").join(path).into_os_string()
  } else {
    path.as_os_str().to_owned()
  }
}

/// Quote a sqlite identifier with doubled internal quotes.
fn quote_identifier(text: &str) -> String {
  format!("\"{}\"", text.replace('"', "\"\""))
}

#[cfg(all(test, not(windows)))]
mod tests {
  use std::path::PathBuf;

  use super::*;

  fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..").join("tests").join(name)
  }

  #[test]
  fn test_path_arg() {
    assert_eq!(OsString::from("./-data.db"), path_arg(Path::new("-data.db")));
    assert_eq!(PathBuf::from("data.db").into_os_string(), path_arg(Path::new("data.db")));
    assert_eq!(PathBuf::from("/tmp/-data.db").into_os_string(), path_arg(Path::new("/tmp/-data.db")));
  }

  #[test]
  fn test_quote_identifier() {
    assert_eq!("\"users\"", quote_identifier("users"));
    assert_eq!("\"a\"\"b\"", quote_identifier("a\"b"));
  }

  #[test]
  fn test_load() {
    let input = load(&fixture("sqlite-single.db"), None).unwrap();
    assert_eq!(["name", "score"], input.headers());
    assert_eq!("alice", input.rows()[0][0]);
    assert!(matches!(load(&fixture("sqlite-single.db"), Some("missing")), Err(Error::SqliteInvalidTable(..))));
  }
}
