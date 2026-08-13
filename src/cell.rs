//! Table cell text and value.

use std::{borrow::Cow, ops::Deref};

use crate::{util, value::Value};

/// Display text plus its normalized numeric value, when the column is numeric.
/// Formatting may change `text`; `value` remains stable for sorting and scales.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Cell {
  text: String,
  value: Option<Value>,
}

impl Cell {
  // Cells parse immediately; Grid later normalizes the column.
  pub(crate) fn parse(text: String) -> Self {
    let value = Value::parse(&text);
    Self { text, value }
  }

  pub(crate) fn as_str(&self) -> &str {
    &self.text
  }

  pub(crate) fn value(&self) -> Option<&Value> {
    self.value.as_ref()
  }

  pub(crate) fn squish(&mut self) {
    if let Cow::Owned(text) = util::squish(&self.text) {
      self.value = Value::parse(&text);
      self.text = text;
    }
  }

  // A string column discards numeric candidates but retains their text.
  pub(crate) fn convert_to_text(&mut self) {
    self.value = None;
  }

  // Mixed int/float columns store one consistent value type.
  pub(crate) fn convert_to_float(&mut self) {
    if let Some(Value::Int(value)) = self.value {
      self.value = Some(Value::Float(value as f64));
    }
  }

  // Render-time formatting changes text without losing the numeric value.
  pub(crate) fn set_text(&mut self, text: String) {
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
