use std::{fmt, fmt::Write as _, path::PathBuf};

//
// Error formatting
//

pub const USAGE_HINT: &str = "tennis: try 'tennis --help' for more information\n";

// User-facing app errors.
#[derive(Debug, Eq, PartialEq)]
pub enum Error {
  BadDeselect(String, Vec<String>),
  BadSelect(String, Vec<String>),
  BadSort(String, Vec<String>),
  Csv,
  FileNotFound(PathBuf),
  FileRead,
  JaggedCsv,
  Json,
  MissingColumn { column: String, operation: Option<tennis::ColumnOperation>, headers: Vec<String> },
  PagerStart,
  TableBuild,
  SqliteCliFailed,
  SqliteCliMissing,
  SqliteInvalidTable(String, Vec<String>),
  SqliteNoTables,
  SqliteRequiresFile,
  SqliteTableRequiresSqlite,
  StdinRead,
}

pub type Result<T> = std::result::Result<T, Error>;

impl fmt::Display for Error {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    f.write_str(&format(self))
  }
}

impl std::error::Error for Error {}

impl From<tennis::Error> for Error {
  fn from(error: tennis::Error) -> Self {
    match error {
      tennis::Error::HeaderLength { .. } | tennis::Error::Jagged { .. } => Self::JaggedCsv,
      tennis::Error::JsonArrayExpected | tennis::Error::JsonObjectExpected => Self::Json,
      tennis::Error::MissingColumn { column, operation, headers } => Self::MissingColumn { column, operation, headers },
      _ => Self::TableBuild,
    }
  }
}

// Plain top-level error without usage guidance.
pub fn message(message: &str) -> String {
  format!("tennis: {message}\n")
}

// Add the help hint only when the user supplied Tennis options incorrectly.
pub fn usage(message: &str) -> String {
  format!("tennis: {message}\n{USAGE_HINT}")
}

fn format(error: &Error) -> String {
  let message = match error {
    Error::BadDeselect(name, headers) => return bad_column_name("--deselect", name, headers),
    Error::BadSelect(name, headers) => return bad_column_name("--select", name, headers),
    Error::BadSort(name, headers) => return bad_column_name("--sort", name, headers),
    Error::Csv => "That CSV file doesn't look right",
    Error::FileNotFound(path) => {
      return message(&format!("Could not read file '{}'", path.display()));
    }
    Error::FileRead => "Could not read that file",
    Error::JaggedCsv => "All csv rows must have same number of columns",
    Error::Json => "That JSON/JSONL file doesn't look right",
    Error::MissingColumn { column, operation, headers } => {
      return missing_column(column, *operation, headers);
    }
    Error::PagerStart => return message("Could not start pager"),
    Error::SqliteCliFailed => "Could not read that file with sqlite3",
    Error::SqliteCliMissing => "`sqlite3` is required, but I couldn't find it.",
    Error::TableBuild => "Failed to build table",
    Error::SqliteInvalidTable(table, tables) => return sqlite_table_error(table, tables),
    Error::SqliteNoTables => "That db has no tables",
    Error::SqliteRequiresFile => "Sqlite requires a file (not a pipe)",
    Error::SqliteTableRequiresSqlite => "--table only works with sqlite files",
    Error::StdinRead => return message("Could not read from stdin"),
  };

  match error {
    Error::SqliteTableRequiresSqlite => usage(message),
    _ => self::message(message),
  }
}

// Column errors are most useful with the bad name and valid source headers.
fn bad_column_name(flag: &str, name: &str, headers: &[String]) -> String {
  let mut out = String::new();
  let _ = writeln!(out, "{flag} didn't look right, should be a comma-separated list of columns.");
  if !name.is_empty() {
    let _ = writeln!(out, "tennis: You wrote: {name}");
  }
  write_name_list(&mut out, "Here are the columns in that file:", headers);
  usage(out.trim_end())
}

fn missing_column(column: &str, operation: Option<tennis::ColumnOperation>, headers: &[String]) -> String {
  let label = match operation {
    Some(tennis::ColumnOperation::Big | tennis::ColumnOperation::Bigger | tennis::ColumnOperation::Biggest) => {
      "-b/-bb/-bbb"
    }
    Some(tennis::ColumnOperation::ColorScale) => "color scale",
    None | Some(_) => "column option",
  };
  bad_column_name(label, column, headers)
}

// A missing sqlite table can usually be fixed by choosing one of the tables
// already present in the file, so list them inline.
fn sqlite_table_error(table: &str, tables: &[String]) -> String {
  let mut out = String::new();
  let _ = writeln!(out, "Table '{table}' was not found in that sqlite file.");
  write_name_list(&mut out, "Here are the tables in that file:", tables);
  message(out.trim_end())
}

// Preserve the `tennis:` prefix on every suggestion line.
fn write_name_list(out: &mut String, label: &str, names: &[String]) {
  let _ = writeln!(out, "tennis: {label}");
  if names.is_empty() {
    out.push_str("tennis:   (none)");
    return;
  }
  for (index, name) in names.iter().enumerate() {
    if index > 0 {
      out.push('\n');
    }
    let _ = write!(out, "tennis:   {name}");
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_bad_column_name() {
    let out = format(&Error::BadSort("scrore".to_owned(), vec!["carat".to_owned(), "cut".to_owned()]));
    assert!(out.contains("tennis: --sort didn't look right"));
    assert!(out.contains("tennis: You wrote: scrore"));
    assert!(out.contains("tennis:   carat"));
  }

  #[test]
  fn test_missing_column() {
    let out = format(&Error::MissingColumn {
      column: "bogus".to_owned(),
      operation: Some(tennis::ColumnOperation::Big),
      headers: vec!["carat".to_owned(), "cut".to_owned()],
    });
    assert!(out.contains("tennis: -b/-bb/-bbb didn't look right"));
    assert!(out.contains("tennis: You wrote: bogus"));
    assert!(out.contains("tennis:   cut"));
  }

  #[test]
  fn test_sqlite_table_error() {
    let out = format(&Error::SqliteInvalidTable("missing".to_owned(), vec!["players".to_owned()]));
    assert!(out.contains("tennis: Table 'missing' was not found"));
    assert!(out.contains("tennis:   players"));
  }
}
