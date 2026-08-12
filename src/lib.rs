//! Public crate surface for tennis.

extern crate self as tennis;

mod border;
mod builder;
mod cell;

mod color_scale;
mod column;
mod context;
mod grid;
mod infer;
mod middleware;
mod resolved;
mod table;
mod theme;
mod util;
mod value;
#[doc(hidden)]
pub mod verbose;

pub use builder::{
  Builder,
  error::{ColumnOperation, Error, Result},
  into_cells::IntoCells,
  into_json::{IntoJsonMap, IntoJsonMaps},
  record::Record,
  types::{Border, ColorMode, ThemeMode, WidthMode},
};
pub use cell::Cell;
pub use color_scale::ColorScale;
pub use grid::Grid;
pub use infer::ColumnType;
pub use table::Table;
pub use tennis_derive::Record;
pub use value::Value;
