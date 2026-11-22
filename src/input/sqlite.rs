use std::{
  ffi::OsString,
  path::{Path, PathBuf},
  process::Command,
};

use crate::{Error, Grid, Result, input::csv};

//
// SQLite loading
//

/// Export the selected sqlite table as CSV, then reuse the CSV loader.
pub fn load(path: &Path, selected_table: Option<&str>) -> Result<Grid> {
  let tables = list_tables(path)?;
  let table = choose_table(path, &tables, selected_table)?;
  let sql = format!("SELECT {} FROM {};", select_list(path, &table)?, quote_identifier(&table));
  // keep -csv before -header! sqlite 3.52-3.53 (and macOS /usr/bin/sqlite3) reset -header on a later
  // mode flag, fixed upstream in d8f6cc7ea4 (bug 2026-06-13T11:49:18Z). see tennis #90
  let stdout = run(path, &["-batch", "-csv", "-header"], &sql)?;
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

/// sqlite3 -csv writes blobs as raw unquoted bytes, which breaks the CSV, so
/// render each blob value as its length instead. Checks typeof per value since
/// any column can hold a blob. table_xinfo keeps generated columns; hidden = 1
/// is virtual-table internals, which SELECT * also skips.
fn select_list(path: &Path, table: &str) -> Result<String> {
  let sql = format!("SELECT name FROM pragma_table_xinfo({}) WHERE hidden != 1;", quote_literal(table));
  let stdout = run(path, &["-batch", "-noheader"], &sql)?;
  let text = String::from_utf8_lossy(&stdout);
  let cols: Vec<String> = text
    .lines()
    .filter(|line| !line.is_empty())
    .map(|name| {
      let col = quote_identifier(name);
      format!("CASE WHEN typeof({col}) = 'blob' THEN '<blob ' || length({col}) || ' bytes>' ELSE {col} END AS {col}")
    })
    .collect();
  if cols.is_empty() { Err(Error::SqliteNoTables) } else { Ok(cols.join(", ")) }
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

/// Quote a sqlite string literal with doubled internal quotes.
fn quote_literal(text: &str) -> String {
  format!("'{}'", text.replace('\'', "''"))
}

#[cfg(all(test, not(windows)))]
mod tests {
  use std::path::PathBuf;

  use super::*;

  fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests").join(name)
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

  #[test]
  fn test_load_blobs() {
    // blobs with newline/comma/quote bytes, a blob in an INTEGER column, and a generated column
    let input = load(&fixture("sqlite-blob.db"), None).unwrap();
    assert_eq!(["name", "data", "odd \"col\"", "upper"], input.headers());
    let rows: Vec<Vec<&str>> = input.rows().iter().map(|row| row.iter().map(|cell| cell.as_str()).collect()).collect();
    assert_eq!(
      vec![vec!["a", "<blob 3 bytes>", "1", "A"], vec!["b", "", "<blob 2 bytes>", "B"], vec!["c", "text", "3", "C"]],
      rows
    );
  }

  #[test]
  fn test_quote_literal() {
    assert_eq!("'users'", quote_literal("users"));
    assert_eq!("'it''s'", quote_literal("it's"));
  }
}
