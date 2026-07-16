use tennis::Grid;

use crate::error::{Error, Result};

//
// CSV loading
//

/// Parse CSV bytes with the selected delimiter.
pub fn load(bytes: &[u8], delimiter: u8) -> Result<Grid> {
  // read csv
  let mut reader = csv::ReaderBuilder::new().has_headers(false).delimiter(delimiter).from_reader(bytes);
  let mut rows: Vec<Vec<String>> = Vec::new();
  for row in reader.byte_records() {
    let row = row.map_err(csv_error)?;
    rows.push(row.iter().map(|f| String::from_utf8_lossy(f).into_owned()).collect());
  }

  // empty?
  if rows.is_empty() {
    return Ok(Grid::new(Vec::new(), Vec::new()).expect("empty grid is rectangular"));
  }

  // => grid
  let headers = rows.remove(0);
  Ok(Grid::new(headers, rows).expect("csv reader rejects jagged rows"))
}

fn csv_error(error: csv::Error) -> Error {
  match error.kind() {
    csv::ErrorKind::UnequalLengths { .. } => Error::JaggedCsv,
    _ => Error::Csv,
  }
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
}
