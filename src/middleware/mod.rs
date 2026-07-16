//! Internal render pipeline middleware.

use crate::context::Context;

// re-export these
pub(crate) mod columns;
pub(crate) mod format;
pub(crate) mod layout;
pub(crate) mod paint;
pub(crate) mod render;
pub(crate) mod truncate;

//
// our pipeline (note that render is handled separately
//

pub(crate) struct Middleware {
  pub(crate) name: &'static str,
  pub(crate) run: for<'w> fn(&mut Context<'w>),
}

pub(crate) const MIDDLEWARE: [Middleware; 5] = [
  Middleware { name: "columns", run: columns::run },
  Middleware { name: "format", run: format::run },
  Middleware { name: "layout", run: layout::run },
  Middleware { name: "paint", run: paint::run },
  Middleware { name: "truncate", run: truncate::run },
];
