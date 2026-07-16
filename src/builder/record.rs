//! Record trait for `Builder::load_records`.

use crate::builder::Builder;

/// A row that can be loaded with `Builder::load_records`.
pub trait Record {
  /// Headers for this record type.
  fn headers() -> Vec<String>;

  /// Apply any derived table settings to the builder.
  fn builder(builder: Builder) -> Builder {
    builder
  }

  /// Convert one record into cells.
  fn to_cells(&self) -> Vec<String>;
}
