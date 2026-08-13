use std::{
  io::{self, Read},
  path::Path,
};

//
// Format detection. First tries filename (if available), then we look for the
// sqlite magic number, then we fallback to json vs. csv detection.
//

const SQLITE_MAGIC: &[u8] = b"SQLite format 3";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InputFormat {
  Csv,
  Json,
  Sqlite,
}

/// what sort of file is this? Try the path, then fallback to sampling some bytes
pub fn detect_format(filename: Option<&Path>, sample: &[u8]) -> InputFormat {
  // take a look at extname
  if let Some(path) = filename {
    let ext = path.extension().and_then(|ext| ext.to_str()).map(|ext| ext.to_ascii_lowercase());
    match ext.as_deref() {
      Some("csv" | "tsv") => return InputFormat::Csv,
      Some("json" | "jsonl" | "ndjson") => return InputFormat::Json,
      Some("db" | "sqlite" | "sqlite3") => return InputFormat::Sqlite,
      _ => {}
    }
  }

  // maigc number
  let magic = &sample[..sample.len().min(16)];
  if magic.starts_with(SQLITE_MAGIC) {
    return InputFormat::Sqlite;
  }

  // json/jsonl heuristic
  let first = magic.iter().copied().find(|byte| !byte.is_ascii_whitespace());
  if matches!(first, Some(b'{' | b'[')) {
    return InputFormat::Json;
  }

  // fallback/default
  InputFormat::Csv
}

/// Is this a sqlite file? Check path and scan few bytes
pub fn is_sqlite_path(path: &Path) -> io::Result<bool> {
  if detect_format(Some(path), &[]) == InputFormat::Sqlite {
    return Ok(true);
  }

  let mut file = std::fs::File::open(path)?;
  let mut sample = [0; 16];
  let n = file.read(&mut sample)?;
  Ok(detect_format(Some(path), &sample[..n]) == InputFormat::Sqlite)
}

#[cfg(test)]
mod tests {
  use std::{
    io::Write,
    time::{SystemTime, UNIX_EPOCH},
  };

  use super::*;

  #[test]
  fn test_detect_format() {
    let cases = [
      (None, b"  [\n  {\"a\":1}\n".as_slice(), InputFormat::Json),
      (None, b"{\"a\":1}\n{\"a\":2}\n", InputFormat::Json),
      (None, b"SQLite format 3\0rest", InputFormat::Sqlite),
      (None, b"a,b\n1,2\n", InputFormat::Csv),
      (None, b"", InputFormat::Csv),
      (Some(Path::new("foo.JSON")), b"a,b\n1,2\n", InputFormat::Json),
      (Some(Path::new("foo.CSV")), b"{\"rows\":[1,2,3]}\n", InputFormat::Csv),
      (Some(Path::new("foo.SQLITE")), b"a,b\n1,2\n", InputFormat::Sqlite),
      (Some(Path::new("foo.TSV")), b"{\"a\":1}\n", InputFormat::Csv),
      (Some(Path::new("foo.NDJSON")), b"{\"a\":1}\n", InputFormat::Json),
      (Some(Path::new("-")), b"[{\"a\":1}]\n", InputFormat::Json),
      (Some(Path::new("foo.txt")), b"SQLite format 3\0rest", InputFormat::Sqlite),
      (Some(Path::new("foo.txt")), b"a,b\n1,2\n", InputFormat::Csv),
    ];

    for (filename, sample, want) in cases {
      assert_eq!(want, detect_format(filename, sample));
    }
  }

  #[test]
  fn test_is_sqlite_path() {
    let dir = std::env::temp_dir()
      .join(format!("tennis-detect-{}", SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()));
    std::fs::create_dir(&dir).unwrap();

    let db_ext = dir.join("data.db");
    std::fs::write(&db_ext, b"not actually sqlite").unwrap();
    assert!(is_sqlite_path(&db_ext).unwrap());

    let magic = dir.join("data.bin");
    let mut file = std::fs::File::create(&magic).unwrap();
    file.write_all(b"SQLite format 3\0rest").unwrap();
    assert!(is_sqlite_path(&magic).unwrap());

    let csv = dir.join("data.txt");
    std::fs::write(&csv, b"a,b\n1,2\n").unwrap();
    assert!(!is_sqlite_path(&csv).unwrap());

    std::fs::remove_dir_all(dir).unwrap();
  }
}
