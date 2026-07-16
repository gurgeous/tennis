//! Conversion for Builder::load_json.

use std::collections::{BTreeMap, HashMap};

use serde_json::{Map, Value};

use crate::builder::{Error, Result};

pub trait IntoJsonMap {
  fn into_json_map(self) -> Result<Vec<(String, Value)>>;
}

pub trait IntoJsonMaps {
  fn into_json_maps(self) -> Result<Vec<Vec<(String, Value)>>>;
}

pub(crate) fn lookup(row: &[(String, Value)], header: &str) -> Option<String> {
  row.iter().find(|(key, _)| key == header).map(|(_, value)| cell(value))
}

fn cell(value: &Value) -> String {
  match value {
    Value::Null => String::new(),
    Value::String(value) => value.clone(),
    Value::Number(value) => value.to_string(),
    Value::Bool(value) => value.to_string(),
    Value::Array(values) => values.iter().map(cell).collect::<Vec<_>>().join(", "),
    Value::Object(value) => serde_json::to_string(value).expect("JSON object serialization should succeed"),
  }
}

impl IntoJsonMap for Map<String, Value> {
  fn into_json_map(self) -> Result<Vec<(String, Value)>> {
    Ok(self.into_iter().collect())
  }
}

impl IntoJsonMap for &Map<String, Value> {
  fn into_json_map(self) -> Result<Vec<(String, Value)>> {
    Ok(self.iter().map(|(key, value)| (key.clone(), value.clone())).collect())
  }
}

impl IntoJsonMap for HashMap<String, Value> {
  fn into_json_map(self) -> Result<Vec<(String, Value)>> {
    Ok(self.into_iter().collect())
  }
}

impl IntoJsonMap for &HashMap<String, Value> {
  fn into_json_map(self) -> Result<Vec<(String, Value)>> {
    Ok(self.iter().map(|(key, value)| (key.clone(), value.clone())).collect())
  }
}

impl IntoJsonMap for BTreeMap<String, Value> {
  fn into_json_map(self) -> Result<Vec<(String, Value)>> {
    Ok(self.into_iter().collect())
  }
}

impl IntoJsonMap for &BTreeMap<String, Value> {
  fn into_json_map(self) -> Result<Vec<(String, Value)>> {
    Ok(self.iter().map(|(key, value)| (key.clone(), value.clone())).collect())
  }
}

impl IntoJsonMap for Value {
  fn into_json_map(self) -> Result<Vec<(String, Value)>> {
    match self {
      Value::Object(row) => Ok(row.into_iter().collect()),
      _ => Err(Error::JsonObjectExpected),
    }
  }
}

impl IntoJsonMaps for Value {
  fn into_json_maps(self) -> Result<Vec<Vec<(String, Value)>>> {
    match self {
      Value::Array(rows) => rows.into_json_maps(),
      _ => Err(Error::JsonArrayExpected),
    }
  }
}

impl IntoJsonMaps for &Value {
  fn into_json_maps(self) -> Result<Vec<Vec<(String, Value)>>> {
    match self {
      Value::Array(rows) => rows.iter().map(IntoJsonMap::into_json_map).collect(),
      _ => Err(Error::JsonArrayExpected),
    }
  }
}

impl<J> IntoJsonMaps for Vec<J>
where
  J: IntoJsonMap,
{
  fn into_json_maps(self) -> Result<Vec<Vec<(String, Value)>>> {
    self.into_iter().map(IntoJsonMap::into_json_map).collect()
  }
}

impl<J, const N: usize> IntoJsonMaps for [J; N]
where
  J: IntoJsonMap,
{
  fn into_json_maps(self) -> Result<Vec<Vec<(String, Value)>>> {
    self.into_iter().map(IntoJsonMap::into_json_map).collect()
  }
}

impl<J> IntoJsonMaps for &[J]
where
  for<'a> &'a J: IntoJsonMap,
{
  fn into_json_maps(self) -> Result<Vec<Vec<(String, Value)>>> {
    self.iter().map(IntoJsonMap::into_json_map).collect()
  }
}

impl IntoJsonMap for &Value {
  fn into_json_map(self) -> Result<Vec<(String, Value)>> {
    match self {
      Value::Object(row) => row.into_json_map(),
      _ => Err(Error::JsonObjectExpected),
    }
  }
}
