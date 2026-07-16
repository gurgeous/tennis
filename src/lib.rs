//! Public crate surface for tennis.

extern crate self as tennis;

mod border;
mod builder;

mod color_scale;
mod column;
mod context;
mod grid;
mod infer;
mod middleware;
#[doc(hidden)]
pub mod number;
mod resolved;
mod table;
mod theme;
mod util;
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
pub use color_scale::ColorScale;
pub use grid::Grid;
pub use infer::ColumnType;
pub use table::Table;
pub use tennis_derive::Record;
