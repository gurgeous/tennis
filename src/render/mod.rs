//! Table rendering.

use std::io;

use anstream::{
  AutoStream, ColorChoice,
  stream::{AsLockedWrite, RawStream},
};

use self::{context::Context, resolved::Resolved};
use crate::{
  Grid,
  middleware::{MIDDLEWARE, render},
  verbose,
};

pub mod ansi256;
pub mod border;
pub mod color_scale;
pub mod column;
pub mod context;
pub mod options;
pub mod resolved;
pub mod theme;

pub fn text(grid: Grid, options: Resolved) -> String {
  let mut out = Vec::new();
  write(grid, options, &mut out).expect("render to Vec cannot fail");
  String::from_utf8(out).expect("renderer writes valid utf-8")
}

pub fn write<W: RawStream + AsLockedWrite + ?Sized>(grid: Grid, options: Resolved, writer: &mut W) -> io::Result<()> {
  // build context
  let choice = match options.color {
    options::ColorMode::On => ColorChoice::Always,
    options::ColorMode::Off => ColorChoice::Never,
    options::ColorMode::Auto => unreachable!("color was resolved before rendering"),
  };
  let mut autostream = AutoStream::new(writer, choice);
  let mut ctx = Context::new(grid, options, &mut autostream);

  // pipeline. note if we skip if empty, middleware doesn't attempt to handle
  // the empty case
  if !ctx.is_empty() {
    for middleware in MIDDLEWARE {
      verbose::time(middleware.name, || (middleware.run)(&mut ctx));
    }
  }

  // now render
  verbose::time("render", || render::run(&mut ctx))
}

// Direct fixtures shared by render-pass tests.
#[cfg(test)]
pub fn test_grid<H, R, C>(headers: H, rows: R) -> Grid
where
  H: IntoIterator,
  H::Item: ToString,
  R: IntoIterator<Item = C>,
  C: IntoIterator,
  C::Item: ToString,
{
  let headers = headers.into_iter().map(|header| header.to_string()).collect();
  let rows = rows.into_iter().map(|row| row.into_iter().map(|cell| cell.to_string()).collect()).collect();
  Grid::new(headers, rows).expect("valid grid")
}

#[cfg(test)]
pub fn test_options() -> Resolved {
  options::RenderOptions {
    color: Some(options::ColorMode::Off),
    theme: Some(options::ThemeMode::Dark),
    width: options::WidthMode::Fixed(80),
    ..options::RenderOptions::default()
  }
  .resolve()
}
