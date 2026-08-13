//! Internal render pipeline middleware.

use crate::render::context::Context;

pub mod columns;
pub mod format;
pub mod layout;
pub mod paint;
pub mod truncate;

//
// our pipeline (note that render is handled separately
//

pub struct Middleware {
  pub name: &'static str,
  pub run: for<'w> fn(&mut Context<'w>),
}

pub const MIDDLEWARE: [Middleware; 5] = [
  Middleware { name: "columns", run: columns::run },
  Middleware { name: "format", run: format::run },
  Middleware { name: "layout", run: layout::run },
  Middleware { name: "paint", run: paint::run },
  Middleware { name: "truncate", run: truncate::run },
];
