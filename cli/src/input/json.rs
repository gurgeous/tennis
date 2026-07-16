use std::collections::HashMap;

use simd_json::{Node, StaticNode};
use tennis::Grid;

use crate::{
  error::{Error, Result},
  util,
};

//
// JSON loading
//
// This path is tuned for big JSON/JSONL. Do not use the crate's serde_json
// handling, that will be too slow for large files. Handles JSON arrays, JSON
// objects, and JSONL.
//

const MAX_COMPACT_DEPTH: usize = 1024;

/// load json/jsonl to grid
pub fn load(bytes: &[u8]) -> Result<Grid> {
  if bytes.is_empty() {
    return Ok(Grid::new(Vec::new(), Vec::new()).expect("empty grid is rectangular"));
  }

  let mut input = bytes.to_vec();
  match simd_json::to_tape(&mut input) {
    Ok(tape) => tape_to_data(&tape.0),
    Err(_) => {
      let mut input = jsonl_to_array(bytes);
      let tape = simd_json::to_tape(&mut input).map_err(|_| Error::Json)?;
      tape_to_data(&tape.0)
    }
  }
}

// Wrap nonblank JSONL lines into one JSON array for simd-json.
fn jsonl_to_array(bytes: &[u8]) -> Vec<u8> {
  let mut out = Vec::with_capacity(bytes.len() + 2);
  out.push(b'[');
  let mut first = true;
  for line in bytes.split(|byte| *byte == b'\n') {
    let line = line.trim_ascii();
    if line.is_empty() {
      continue;
    }
    if first {
      first = false;
    } else {
      out.push(b',');
    }
    out.extend_from_slice(line);
  }
  out.push(b']');
  out
}

// Dispatch a simd-json tape by top-level shape.
fn tape_to_data(nodes: &[Node<'_>]) -> Result<Grid> {
  match nodes.first() {
    Some(Node::Array { len, .. }) => objects_to_data(nodes, 1, *len),
    Some(Node::Object { len, .. }) => object_to_key_value_data(nodes, 0, *len),
    _ => Err(Error::Json),
  }
}

// Convert a top-level object into key/value rows, with duplicate keys
// last-wins.
fn object_to_key_value_data(nodes: &[Node<'_>], index: usize, len: usize) -> Result<Grid> {
  let mut keys = Vec::new();
  let mut index_by_name = HashMap::with_capacity(len);
  let mut values = Vec::new();

  let mut index = index + 1;
  for _ in 0..len {
    let key = node_string(nodes, index).to_owned();
    index += 1;
    let value = cell_to_string(nodes, index)?;
    index += node_count(nodes, index);
    if let Some(&index) = index_by_name.get(key.as_str()) {
      values[index] = value;
    } else {
      index_by_name.insert(key.clone(), keys.len());
      keys.push(key);
      values.push(value);
    }
  }
  let rows = keys.into_iter().zip(values).map(|(k, v)| vec![k, v]).collect();
  Ok(Grid::new(vec!["key".to_owned(), "value".to_owned()], rows).expect("json object loader builds key/value rows"))
}

// Convert an array of objects into rectangular rows with first-seen header
// order.
fn objects_to_data(nodes: &[Node<'_>], mut index: usize, len: usize) -> Result<Grid> {
  let mut headers = Vec::new();
  let mut index_by_name = HashMap::new();
  // Collect (col, value) pairs per row; defer expansion so all rows are
  // padded to the final header count even when new columns appear mid-stream.
  let mut row_pairs: Vec<Vec<(usize, String)>> = Vec::with_capacity(len);

  for _ in 0..len {
    let Node::Object { len, .. } = nodes.get(index).ok_or(Error::Json)? else {
      return Err(Error::Json);
    };
    let mut pairs = Vec::with_capacity(*len);
    let mut child = index + 1;
    for _ in 0..*len {
      let key = node_string(nodes, child);
      child += 1;
      let col = if let Some(&col) = index_by_name.get(key) {
        col
      } else {
        let col = headers.len();
        index_by_name.insert(key.to_owned(), col);
        headers.push(key.to_owned());
        col
      };
      let value = cell_to_string(nodes, child)?;
      child += node_count(nodes, child);
      pairs.push((col, value));
    }
    row_pairs.push(pairs);
    index += node_count(nodes, index);
  }

  // Expand pairs into full-width rows now that all headers are known.
  let rows: Vec<Vec<String>> = row_pairs
    .into_iter()
    .map(|pairs| {
      let mut fields = vec![String::new(); headers.len()];
      for (ci, value) in pairs {
        fields[ci] = value;
      }
      fields
    })
    .collect();

  Ok(Grid::new(headers, rows).expect("json loader builds rectangular rows"))
}

// Convert one tape value into display cell text.
fn cell_to_string(nodes: &[Node<'_>], index: usize) -> Result<String> {
  match &nodes[index] {
    Node::String(value) => Ok((*value).to_owned()),
    Node::Static(StaticNode::Null) => Ok(String::new()),
    Node::Static(value) => Ok(static_to_string(value)),
    Node::Array { .. } | Node::Object { .. } => {
      let mut out = String::new();
      compact_into(nodes, index, &mut out, 0)?;
      Ok(out)
    }
  }
}

// Render nested arrays/objects as compact JSON without risking unbounded
// recursion.
fn compact_into(nodes: &[Node<'_>], index: usize, out: &mut String, depth: usize) -> Result<()> {
  if depth > MAX_COMPACT_DEPTH {
    return Err(Error::Json);
  }
  match &nodes[index] {
    Node::String(value) => out.push_str(&util::json_escape(value)),
    Node::Static(StaticNode::Null) => out.push_str("null"),
    Node::Static(value) => out.push_str(&static_to_string(value)),
    Node::Array { len, .. } => {
      out.push('[');
      let mut child = index + 1;
      for item in 0..*len {
        if item > 0 {
          out.push_str(", ");
        }
        compact_into(nodes, child, out, depth + 1)?;
        child += node_count(nodes, child);
      }
      out.push(']');
    }
    Node::Object { len, .. } => {
      out.push('{');
      let mut child = index + 1;
      for item in 0..*len {
        if item > 0 {
          out.push_str(", ");
        }
        let key = node_string(nodes, child);
        out.push_str(&util::json_escape(key));
        out.push(':');
        child += 1;
        compact_into(nodes, child, out, depth + 1)?;
        child += node_count(nodes, child);
      }
      out.push('}');
    }
  }
  Ok(())
}

/// Read an object key from the tape.
fn node_string<'a>(nodes: &'a [Node<'a>], index: usize) -> &'a str {
  let Node::String(value) = &nodes[index] else {
    unreachable!("simd-json object keys are strings");
  };
  value
}

/// Return the number of tape nodes occupied by one value.
fn node_count(nodes: &[Node<'_>], index: usize) -> usize {
  match &nodes[index] {
    Node::Object { count, .. } | Node::Array { count, .. } => count + 1,
    Node::String(_) | Node::Static(_) => 1,
  }
}

/// Format scalar tape values with Rust's native formatting.
fn static_to_string(value: &StaticNode) -> String {
  match value {
    StaticNode::Bool(value) => value.to_string(),
    StaticNode::I64(value) => value.to_string(),
    StaticNode::U64(value) => value.to_string(),
    StaticNode::F64(value) => value.to_string(),
    StaticNode::Null => String::new(),
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_load() {
    let input =
      load(br#"[{"name":"alice","score":1234,"tags":["a","b"]},{"name":"bob","city":"denver","meta":{"ok":true}}]"#)
        .unwrap();
    assert_eq!(["name", "score", "tags", "city", "meta"], input.headers());
    assert_eq!("[\"a\", \"b\"]", input.rows()[0][2]);
    assert_eq!("{\"ok\":true}", input.rows()[1][4]);

    let input = load(br#"{"name":"alice","score":1234}"#).unwrap();
    assert_eq!(["key", "value"], input.headers());
    assert_eq!(["name", "alice"], input.rows()[0].as_slice());

    let input = load(b"{\"name\":\"alice\"}\n{\"name\":\"bob\"}").unwrap();
    assert_eq!("bob", input.rows()[1][0]);

    let input = load(b"{\"name\":\"alice\"}\r\n{\"name\":\"bob\"}\r\n").unwrap();
    assert_eq!("bob", input.rows()[1][0]);

    let input = load(b"{\"name\":\"alice\"}\n\n{\"name\":\"bob\"}\n").unwrap();
    assert_eq!("bob", input.rows()[1][0]);
  }

  #[test]
  fn test_load_jsonl_escapes() {
    let input = load(
      br#"{"name":"a\tb","x":1}
{"name":"c","x":2}"#,
    )
    .unwrap();
    assert_eq!("a b", input.rows()[0][0]);
    assert_eq!("c", input.rows()[1][0]);
  }

  #[test]
  fn test_load_streamed_values() {
    assert!(matches!(load(br#"{"name":"alice"} {"name":"bob"}"#), Err(Error::Json)));
  }

  #[test]
  fn test_load_large_ints() {
    assert!(matches!(load(br#"[{"n":-9223372036854775809},{"n":123456789012345678901234567890}]"#), Err(Error::Json)));
  }

  #[test]
  fn test_load_duplicate_top_level_keys() {
    let input = load(br#"{"a":1,"a":2}"#).unwrap();
    assert_eq!(["key", "value"], input.headers());
    assert_eq!(["a", "2"], input.rows()[0].as_slice());
  }

  #[test]
  fn test_load_deep_nested_cell() {
    let value = format!(r#"[{{"x":{}}}]"#, "[".repeat(MAX_COMPACT_DEPTH + 2) + &"]".repeat(MAX_COMPACT_DEPTH + 2));
    assert!(matches!(load(value.as_bytes()), Err(Error::Json)));
  }
}
