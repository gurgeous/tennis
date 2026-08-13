//! Column type inference.

use std::fmt;

use crate::{Cell, Value};

/// What kind of column is this?
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum ColumnType {
  #[default]
  String,
  Float,
  Int,
  Percent,
}

impl fmt::Display for ColumnType {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    let name = match self {
      Self::Float => "float",
      Self::Int => "int",
      Self::Percent => "percent",
      Self::String => "string",
    };
    f.write_str(name)
  }
}

//
// don't infer on these columns, which are often false-positives
//

const TEXT_HEADERS: &[&str] = &[
  // zip codes
  "zip",
  "zipcode",
  "zip_code",
  "zip5",
  "zip_5",
  "zip9",
  "zip_9",
  // postal codes
  "postal",
  "postalcode",
  "postal_code",
  "postcode",
  // phone numbers
  "phone",
  "phone_number",
  "tel",
  "telephone",
  "fax",
  "cell",
  "cell_phone",
  "mobile",
  "mobile_number",
  // tax identifiers
  "ssn",
  "ein",
  "tax_id",
  // product and classification codes
  "ean",
  "fips",
  "gtin",
  "isbn",
  "naics",
  "sic",
  "sku",
  "upc",
];

//
// infer
//

pub fn infer_column_type<'a>(header: &str, cells: impl IntoIterator<Item = &'a Cell>) -> ColumnType {
  if header_forces_text(header) {
    return ColumnType::String;
  }

  let mut floats = false;
  let mut ints = false;
  let mut percents = false;

  for cell in cells.into_iter().filter(|cell| !cell.is_empty()) {
    match cell.value() {
      Some(Value::Int(_)) => ints = true,
      Some(Value::Float(_)) => floats = true,
      Some(Value::Percent(_)) => percents = true,
      None => return ColumnType::String,
    }
  }

  if percents && (ints || floats) {
    ColumnType::String
  } else if floats {
    ColumnType::Float
  } else if ints {
    ColumnType::Int
  } else if percents {
    ColumnType::Percent
  } else {
    ColumnType::String
  }
}

fn header_forces_text(header: &str) -> bool {
  TEXT_HEADERS.iter().any(|candidate| header.eq_ignore_ascii_case(candidate))
}

#[cfg(test)]
mod tests {
  use super::*;

  fn infer(header: &str, values: &[&str]) -> ColumnType {
    let cells = values.iter().map(|value| Cell::from(*value)).collect::<Vec<_>>();
    infer_column_type(header, &cells)
  }

  #[test]
  fn test_infer_type_edge_cases() {
    for (header, values, want) in [
      ("score", &["1234"][..], ColumnType::Int),
      ("score", &["1234.0"], ColumnType::Float),
      ("score", &["12%", "-3.5%"], ColumnType::Percent),
      ("score", &["1", "2%"], ColumnType::String),
      ("score", &["", ""], ColumnType::String),
      ("year", &["2024"], ColumnType::Int),
    ] {
      assert_eq!(want, infer(header, values), "{header}");
    }
  }

  #[test]
  fn test_text_headers_skip_infer() {
    for header in ["ZIPCODE", "phone_number", "sku"] {
      assert_eq!(ColumnType::String, infer(header, &["90210"]), "{header}");
    }
  }

  #[test]
  fn test_text_headers_do_not_match_substrings() {
    for header in ["grid", "zipcode_extra", "home zip", "phone_number_alt", "id", "year"] {
      assert_eq!(ColumnType::Int, infer(header, &["90210"]), "{header}");
    }
  }

  #[test]
  fn test_infer_type_checks_whole_column() {
    let mut cells = vec!["1234"; 200];
    cells[50] = "later-text";
    let cells = cells.into_iter().map(Cell::from).collect::<Vec<_>>();
    assert_eq!(ColumnType::String, infer_column_type("score", &cells));
  }

  #[test]
  fn test_infer_type_late_float_promotes_int_to_float() {
    let mut cells = vec!["28"; 200];
    cells[50] = "28.5";
    let cells = cells.into_iter().map(Cell::from).collect::<Vec<_>>();
    assert_eq!(ColumnType::Float, infer_column_type("age", &cells));
  }
}
