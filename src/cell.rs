//! Table cell text, style, and value.

use std::{borrow::Cow, ops::Deref, rc::Rc};

use crate::{Value, util};

/// Display text plus an optional incoming style and normalized numeric value.
/// Formatting may change `text`; `value` remains stable for sorting and scales.
#[derive(Clone, Debug, PartialEq)]
pub struct Cell {
  text: String,
  style: Option<Rc<String>>,
  value: Option<Value>,
}

impl Cell {
  // Numeric values parse immediately; Grid later normalizes the column.
  pub fn parse(text: String) -> Self {
    Self::parse_styled(text, None)
  }

  pub fn parse_styled(text: String, style: Option<Rc<String>>) -> Self {
    let value = Value::parse(&text);
    Self { text, style, value }
  }

  pub fn as_str(&self) -> &str {
    &self.text
  }

  pub fn value(&self) -> Option<&Value> {
    self.value.as_ref()
  }

  pub fn style(&self) -> Option<&str> {
    self.style.as_deref().map(String::as_str)
  }

  pub fn squish(&mut self) {
    if let Cow::Owned(text) = util::squish(&self.text) {
      self.value = Value::parse(&text);
      self.text = text;
    }
  }

  // A string column discards numeric candidates but retains their text.
  pub fn convert_to_text(&mut self) {
    self.value = None;
  }

  // Mixed int/float columns store one consistent value type.
  pub fn convert_to_float(&mut self) {
    if let Some(Value::Int(value)) = self.value {
      self.value = Some(Value::Float(value as f64));
    }
  }

  // Render-time formatting changes text without losing the numeric value.
  pub fn set_text(&mut self, text: String) {
    self.text = text;
  }
}

// String-like conveniences

impl Deref for Cell {
  type Target = str;

  fn deref(&self) -> &Self::Target {
    &self.text
  }
}

impl AsRef<str> for Cell {
  fn as_ref(&self) -> &str {
    &self.text
  }
}

impl From<String> for Cell {
  fn from(text: String) -> Self {
    Self::parse(text)
  }
}

impl From<&str> for Cell {
  fn from(text: &str) -> Self {
    Self::parse(text.to_owned())
  }
}

impl PartialEq<str> for Cell {
  fn eq(&self, other: &str) -> bool {
    self.text == other
  }
}

impl PartialEq<&str> for Cell {
  fn eq(&self, other: &&str) -> bool {
    self.text == *other
  }
}

impl PartialEq<Cell> for str {
  fn eq(&self, other: &Cell) -> bool {
    self == other.text
  }
}

impl PartialEq<Cell> for &str {
  fn eq(&self, other: &Cell) -> bool {
    *self == other.text
  }
}

impl PartialEq<Cell> for String {
  fn eq(&self, other: &Cell) -> bool {
    self == &other.text
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_squish_preserves_style() {
    let mut cell = Cell::parse_styled(" alice  smith ".to_owned(), Some(Rc::new("\x1b[31m".to_owned())));
    cell.squish();
    assert_eq!("alice smith", cell.as_str());
    assert_eq!(Some("\x1b[31m"), cell.style());
  }
}
