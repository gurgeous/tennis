//! Crate error and result types.

use std::{error as std_error, fmt};

pub type Result<T> = std::result::Result<T, Error>;

#[non_exhaustive]
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Error {
  HeaderLength { expected: usize, actual: usize },
  Jagged { expected: usize, actual: usize },
  JsonArrayExpected,
  JsonObjectExpected,
  MissingColumn { column: String, operation: Option<ColumnOperation>, headers: Vec<String> },
}

#[non_exhaustive]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ColumnOperation {
  Big,
  Bigger,
  Biggest,
  ColorScale,
}

impl fmt::Display for Error {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    match self {
      Self::HeaderLength { expected, actual } => {
        write!(f, "record has {actual} cells, expected {expected} headers")
      }
      Self::Jagged { expected, actual } => write!(f, "row has {actual} cells, expected {expected}"),
      Self::JsonArrayExpected => f.write_str("json value must be an array"),
      Self::JsonObjectExpected => f.write_str("json row must be an object"),
      Self::MissingColumn { column, operation: Some(operation), .. } => {
        write!(f, "missing column for {operation}: {column}")
      }
      Self::MissingColumn { column, operation: None, .. } => {
        write!(f, "missing column: {column}")
      }
    }
  }
}

impl fmt::Display for ColumnOperation {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    match self {
      Self::Big => f.write_str("big"),
      Self::Bigger => f.write_str("bigger"),
      Self::Biggest => f.write_str("biggest"),
      Self::ColorScale => f.write_str("color scale"),
    }
  }
}

impl std_error::Error for Error {}
