//! Private render pipeline state, rebuilt fresh for each render.

use std::{collections::HashMap, io::Write};

use super::{
  border::{self, BorderDraw},
  column::Column,
  resolved::ResolvedOptions,
  theme::{Ansi, Theme},
};
use crate::grid::Grid;

pub type Links = HashMap<(usize, usize), String>;

pub struct Context<'w> {
  // inputs
  pub grid: Grid,
  pub options: ResolvedOptions,
  pub writer: &'w mut dyn Write,

  // populated in ctor
  pub border: BorderDraw, // border info
  pub left: String,       // sep
  pub mid: String,        // sep
  pub right: String,      // sep
  pub theme: Theme,       // theme

  // populated along the way
  pub columns: Vec<Column>, // our cols
  pub links: Links,         // hyperlinks
  pub paint: PaintState,    // style info
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct PaintState {
  pub title: Ansi,
  pub footer: Ansi,
  pub headers: Vec<Ansi>,
  pub columns: Vec<Ansi>,
  pub rows: Vec<Ansi>,
  pub cells: HashMap<(usize, usize), Ansi>,
}

impl<'w> Context<'w> {
  pub fn new<W: Write + 'w>(grid: Grid, options: ResolvedOptions, writer: &'w mut W) -> Self {
    // ordered
    let theme = Theme::new(&options);
    let border = border::get_border(options.border);
    let left = theme.chrome.clone() + &border.left;
    let mid = theme.chrome.clone() + &border.mid;
    let right = theme.chrome.clone() + &border.right;

    Self {
      border,
      columns: Vec::new(),
      grid,
      links: HashMap::new(),
      options,
      paint: PaintState::default(),
      left,
      mid,
      right,
      theme,
      writer,
    }
  }

  pub fn nrows(&self) -> usize {
    self.grid.rows.len()
  }

  pub fn ncols(&self) -> usize {
    self.columns.len()
  }

  pub fn is_empty(&self) -> bool {
    self.grid.is_empty()
  }
}
