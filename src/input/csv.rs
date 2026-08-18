use std::rc::Rc;

use crate::{Cell, Error, Grid, Result};

const ESC: u8 = b'\x1b';
const RESET: &str = "\x1b[0m";
const SHORT_RESET: &str = "\x1b[m";

//
// CSV loading
//

/// Parse CSV bytes with the selected delimiter.
pub fn load(bytes: &[u8], delimiter: u8) -> Result<Grid> {
  // 20k rows × 12 cells, 10 release runs: main 26.62 ms; plain 28.38 ms;
  // ANSI on 1% of rows 30.24 ms.
  if memchr::memchr(ESC, bytes).is_some() { load_ansi(bytes, delimiter) } else { load_plain(bytes, delimiter) }
}

fn load_plain(bytes: &[u8], delimiter: u8) -> Result<Grid> {
  let mut reader = csv::ReaderBuilder::new().has_headers(false).delimiter(delimiter).from_reader(bytes);
  let mut records = reader.byte_records();
  let Some(headers) = records.next() else {
    return Ok(Grid::new(Vec::new(), Vec::new()).expect("empty grid is rectangular"));
  };
  let headers = csv::StringRecord::from_byte_record_lossy(headers.map_err(csv_error)?);
  let headers = headers.iter().map(str::to_owned).collect();

  let mut rows = Vec::new();
  for row in records {
    let row = csv::StringRecord::from_byte_record_lossy(row.map_err(csv_error)?);
    rows.push(row.iter().map(Cell::from).collect());
  }
  Ok(Grid::from_cells(headers, rows).expect("csv reader rejects jagged rows"))
}

fn load_ansi(bytes: &[u8], delimiter: u8) -> Result<Grid> {
  let mut reader = csv::ReaderBuilder::new().has_headers(false).delimiter(delimiter).from_reader(bytes);
  let mut records = reader.byte_records();
  let Some(headers) = records.next() else {
    return Ok(Grid::new(Vec::new(), Vec::new()).expect("empty grid is rectangular"));
  };
  let headers = csv::StringRecord::from_byte_record_lossy(headers.map_err(csv_error)?);
  let headers = headers.iter().map(strip_ansi).collect();

  let mut rows = Vec::new();
  for row in records {
    let row = csv::StringRecord::from_byte_record_lossy(row.map_err(csv_error)?);
    rows.push(parse_ansi_row(&row));
  }
  Ok(Grid::from_cells(headers, rows).expect("csv reader rejects jagged rows"))
}

fn csv_error(error: csv::Error) -> Error {
  match error.kind() {
    csv::ErrorKind::UnequalLengths { .. } => Error::JaggedCsv,
    _ => Error::Csv,
  }
}

//
// ansi helpers
//

fn parse_ansi_row(row: &csv::StringRecord) -> Vec<Cell> {
  let mut cur = None;
  row
    .iter()
    .map(|text| {
      if !text.as_bytes().contains(&ESC) {
        return Cell::parse_styled(text.to_owned(), cur.clone());
      }

      // check out start/end of cell
      let opening_sgr = opening_sgr(text);
      let closing_reset = ends_with_reset(text);
      if let Some(style) = opening_sgr {
        cur = Some(Rc::new(style.to_owned()));
      }

      // create cell
      let cell = Cell::parse_styled(strip_ansi(text), cur.clone());

      if closing_reset {
        cur = None;
      }
      cell
    })
    .collect()
}

fn opening_sgr(text: &str) -> Option<&str> {
  let bytes = text.as_bytes();
  if !bytes.starts_with(b"\x1b[") {
    return None;
  }
  let end = bytes[2..].iter().position(|byte| *byte == b'm')? + 3;
  let sgr = bytes[2..end - 1].iter().all(|byte| byte.is_ascii_digit() || *byte == b';').then(|| &text[..end])?;
  (!is_reset(sgr)).then_some(sgr)
}

fn is_reset(code: &str) -> bool {
  matches!(code, RESET | SHORT_RESET)
}

fn ends_with_reset(text: &str) -> bool {
  text.ends_with(RESET) || text.ends_with(SHORT_RESET)
}

fn strip_ansi(text: &str) -> String {
  if !text.as_bytes().contains(&ESC) {
    return text.to_owned();
  }
  anstream::adapter::strip_str(text).to_string()
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_load_quotes() {
    let input = load(b"a,b\n\"x,y\",\"say \"\"hi\"\"\"\n", b',').unwrap();
    assert_eq!(["a", "b"], input.headers());
    assert_eq!("x,y", input.rows()[0][0]);
    assert_eq!("say \"hi\"", input.rows()[0][1]);
    assert_eq!(Err(Error::JaggedCsv), load(b"a,b\nc\n", b','));
  }

  #[test]
  fn test_load_controls() {
    let input = load(b"a,b,c\n1,,3\n\"x\ny\",z,\n", b',').unwrap();
    assert_eq!("", input.rows()[0][1]);
    assert_eq!("x y", input.rows()[1][0]);
  }

  #[test]
  fn test_load_replaces_invalid_utf8() {
    let input = load(b"a,b\n\xff,2\n", b',').unwrap();
    assert_eq!("\u{fffd}", input.rows()[0][0]);
    assert_eq!("2", input.rows()[0][1]);
  }

  #[test]
  fn test_load_ansi_styles() {
    let input = load(
      b"\x1b[1mname\x1b[0m,status,detail,note\nAlice,\x1b[31mfailed,bo\x1b[32mom\x1b[0m,fine\nBob,\x1b[31mbad,ok,done\x1b[m\n",
      b',',
    )
    .unwrap();
    assert_eq!(["name", "status", "detail", "note"], input.headers());
    assert_eq!("failed", input.rows()[0][1].as_str());
    assert_eq!("boom", input.rows()[0][2].as_str());
    assert_eq!(Some("\x1b[31m"), input.rows()[0][1].style());
    assert_eq!(Some("\x1b[31m"), input.rows()[0][2].style());
    assert_eq!(None, input.rows()[0][3].style());
    assert_eq!(Some("\x1b[31m"), input.rows()[1][1].style());
    assert_eq!(Some("\x1b[31m"), input.rows()[1][2].style());
    assert_eq!(Some("\x1b[31m"), input.rows()[1][3].style());
  }

  #[test]
  fn test_opening_sgr() {
    assert_eq!(Some("\x1b[31m"), opening_sgr("\x1b[31mred\x1b[0m"));
    assert_eq!(Some("\x1b[38;2;1;2;3m"), opening_sgr("\x1b[38;2;1;2;3mred"));
    assert_eq!(None, opening_sgr("\x1b[0mplain"));
    assert_eq!(None, opening_sgr("plain\x1b[31mred"));
    assert_eq!(None, opening_sgr("\x1b[31xred"));
  }

  #[test]
  fn test_reset() {
    assert!(is_reset("\x1b[0m"));
    assert!(is_reset("\x1b[m"));
    assert!(!is_reset("\x1b[31m"));
    assert!(ends_with_reset("red\x1b[0m"));
    assert!(!ends_with_reset("red\x1b[0m "));
  }
}
