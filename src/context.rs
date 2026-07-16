//! Private render pipeline state, rebuilt fresh for each render.

use std::{collections::HashMap, io::Write};

use crate::{
  Table,
  border::{self, BorderDraw},
  column::Column,
  grid::Grid,
  resolved::Resolved,
  theme::{Ansi, Theme},
};

pub(crate) type Links = HashMap<(usize, usize), String>;

pub(crate) struct Context<'w> {
  // inputs
  pub(crate) grid: Grid,
  pub(crate) options: Resolved,
  pub(crate) writer: &'w mut dyn Write,

  // populated in ctor
  pub(crate) border: BorderDraw, // border info
  pub(crate) left: String,       // sep
  pub(crate) mid: String,        // sep
  pub(crate) right: String,      // sep
  pub(crate) theme: Theme,       // theme

  // populated along the way
  pub(crate) columns: Vec<Column>, // our cols
  pub(crate) links: Links,         // hyperlinks
  pub(crate) paint: PaintState,    // style info
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub(crate) struct PaintState {
  pub(crate) title: Ansi,
  pub(crate) footer: Ansi,
  pub(crate) headers: Vec<Ansi>,
  pub(crate) columns: Vec<Ansi>,
  pub(crate) rows: Vec<Ansi>,
  pub(crate) cells: HashMap<(usize, usize), Ansi>,
}

impl<'w> Context<'w> {
  pub(crate) fn new<W: Write + 'w>(table: Table, writer: &'w mut W) -> Self {
    let Table { grid, options } = table;

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

  pub(crate) fn nrows(&self) -> usize {
    self.grid.rows.len()
  }

  pub(crate) fn ncols(&self) -> usize {
    self.columns.len()
  }

  pub(crate) fn is_empty(&self) -> bool {
    self.grid.is_empty()
  }
}
