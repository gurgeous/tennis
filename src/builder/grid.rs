//! Convert various shapes into Grid

use std::collections::BTreeSet;

use serde_json::Value;

use crate::{
  builder::{Error, Result, into_json},
  grid::Grid,
};

type Lookup<V> = fn(&[(String, V)], &str) -> Option<String>;

pub(crate) fn from_cells(rows: Vec<Vec<String>>) -> Result<Grid> {
  let width = rows.iter().map(Vec::len).max().unwrap_or(0);
  let headers = (1..=width).map(|index| index.to_string()).collect::<Vec<_>>();
  let rows = rows.into_iter().map(|row| pad_row(row, width)).collect();
  Grid::new(headers, rows)
}

pub(crate) fn from_maps(maps: Vec<Vec<(String, String)>>) -> Result<Grid> {
  from_key_values(maps, lookup_string)
}

pub(crate) fn from_json(maps: Vec<Vec<(String, Value)>>) -> Result<Grid> {
  from_key_values(maps, into_json::lookup)
}

pub(crate) fn from_record_cells(source_headers: Vec<String>, record_rows: Vec<Vec<String>>) -> Result<Grid> {
  let rows = record_rows
    .into_iter()
    .map(|row| {
      if row.len() != source_headers.len() {
        Err(Error::HeaderLength { expected: source_headers.len(), actual: row.len() })
      } else {
        Ok(row)
      }
    })
    .collect::<Result<Vec<_>>>()?;
  Grid::new(source_headers, rows)
}

fn pad_row(mut row: Vec<String>, width: usize) -> Vec<String> {
  row.resize(width, String::new());
  row
}

fn from_key_values<V>(maps: Vec<Vec<(String, V)>>, lookup: Lookup<V>) -> Result<Grid> {
  let columns = infer_headers(&maps);
  let rows = maps
    .iter()
    .map(|map| columns.iter().map(|column| lookup(map, column).unwrap_or_default()).collect::<Vec<_>>())
    .collect();
  Grid::new(columns, rows)
}

fn infer_headers<V>(rows: &[Vec<(String, V)>]) -> Vec<String> {
  let mut seen = BTreeSet::new();
  let mut headers = Vec::new();
  // HashMap iteration order is intentionally not stable, so inferred headers
  // from HashMap inputs can vary. Note this in the README before publishing.
  for key in rows.iter().flat_map(|row| row.iter().map(|(key, _)| key)) {
    if seen.insert(key.clone()) {
      headers.push(key.clone());
    }
  }
  headers
}

fn lookup_string(row: &[(String, String)], header: &str) -> Option<String> {
  row.iter().find(|(key, _)| key == header).map(|(_, value)| value.clone())
}

#[cfg(test)]
mod tests {
  use std::collections::BTreeMap;

  use serde_json::json;

  use super::*;
  use crate::builder::record::Record;

  #[test]
  fn test_cells_infer_headers_and_pad_rows() {
    let grid =
      from_cells(vec![vec!["alice".to_owned()], vec!["bob".to_owned(), "5678".to_owned()]]).expect("grid should build");
    assert_eq!(["1", "2"], grid.headers.as_slice());
    assert_eq!(vec!["alice".to_owned(), String::new()], grid.rows[0]);
  }

  #[test]
  fn test_maps_infer_headers_and_project_sparse_rows() {
    let rows = vec![
      BTreeMap::from([("name".to_owned(), "alice".to_owned()), ("score".to_owned(), "1234".to_owned())])
        .into_iter()
        .collect(),
      BTreeMap::from([("name".to_owned(), "bob".to_owned())]).into_iter().collect(),
    ];

    let grid = from_maps(rows).expect("grid should build");
    assert_eq!(["name", "score"], grid.headers.as_slice());
    assert_eq!(vec!["bob".to_owned(), String::new()], grid.rows[1]);
  }

  #[test]
  fn test_maps_allow_empty_input() {
    let grid = from_maps(Vec::new()).expect("grid should build");
    assert!(grid.headers.is_empty());
    assert!(grid.rows.is_empty());
  }

  #[test]
  fn test_json_project_sparse_rows() {
    let rows = vec![
      vec![("name".to_owned(), json!("alice")), ("score".to_owned(), json!(1234))],
      vec![("name".to_owned(), json!("bob"))],
    ];
    let grid = from_json(rows).expect("grid should build");
    assert_eq!(vec!["bob".to_owned(), String::new()], grid.rows[1]);
  }

  #[test]
  fn test_json_allow_empty_input() {
    let grid = from_json(Vec::new()).expect("grid should build");
    assert!(grid.headers.is_empty());
    assert!(grid.rows.is_empty());
  }

  #[test]
  fn test_records() {
    struct Person {
      name: String,
      score: u32,
    }

    impl Record for Person {
      fn headers() -> Vec<String> {
        vec!["name".to_owned(), "score".to_owned()]
      }

      fn to_cells(&self) -> Vec<String> {
        vec![self.name.clone(), self.score.to_string()]
      }
    }

    let people = [Person { name: "alice".to_owned(), score: 1234 }];
    let rows = people.into_iter().map(|person| person.to_cells()).collect();
    let grid = from_record_cells(Person::headers(), rows).expect("grid should build");
    assert_eq!(["name", "score"], grid.headers.as_slice());
    assert_eq!(vec![vec!["alice".to_owned(), "1234".to_owned()]], grid.rows);
  }

  #[test]
  fn test_records_error_when_record_cell_count_does_not_match_headers() {
    struct BadRecord;

    impl Record for BadRecord {
      fn headers() -> Vec<String> {
        vec!["name".to_owned(), "score".to_owned()]
      }

      fn to_cells(&self) -> Vec<String> {
        vec!["alice".to_owned()]
      }
    }

    let rows = [BadRecord].into_iter().map(|record| record.to_cells()).collect();
    let error = from_record_cells(BadRecord::headers(), rows).unwrap_err();
    assert_eq!(Error::HeaderLength { expected: 2, actual: 1 }, error);
  }
}
