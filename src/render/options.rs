//! Render settings.

use super::{
  color_scale::ColorScale,
  resolved::{ResolvedOptions, ResolvedWidth, resolve_color, resolve_theme, terminal_width},
};
use crate::{ColumnOperation, Error, Grid, Result};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RenderOptions {
  pub bigs: Vec<(String, ColumnBig)>,
  pub border: Border,
  pub color: Option<ColorMode>,
  pub color_scales: Vec<(String, ColorScale)>,
  pub digits: usize,
  pub footer: Option<String>,
  pub row_numbers: bool,
  pub theme: Option<ThemeMode>,
  pub title: Option<String>,
  pub vanilla: bool,
  pub width: WidthMode,
  pub zebra: bool,
}

impl Default for RenderOptions {
  fn default() -> Self {
    Self {
      bigs: Vec::new(),
      border: Border::Rounded,
      color: None,
      color_scales: Vec::new(),
      digits: 3,
      footer: None,
      row_numbers: false,
      theme: None,
      title: None,
      vanilla: false,
      width: WidthMode::Auto,
      zebra: false,
    }
  }
}

impl RenderOptions {
  pub fn validate(&self, grid: &Grid) -> Result<()> {
    for (name, big) in &self.bigs {
      grid.position(name).map_err(|_| Error::MissingColumn {
        column: name.clone(),
        operation: big.operation(),
        headers: grid.headers().to_vec(),
      })?;
    }
    for (name, _) in &self.color_scales {
      grid.position(name).map_err(|_| Error::MissingColumn {
        column: name.clone(),
        operation: Some(ColumnOperation::ColorScale),
        headers: grid.headers().to_vec(),
      })?;
    }
    Ok(())
  }

  pub fn resolve(self) -> ResolvedOptions {
    // Finalize terminal-sensitive settings before rendering. Render passes
    // assume concrete color/theme values and never start terminal probes.
    let color = resolve_color(self.color);
    let (theme, termbg) = resolve_theme(color, self.theme);
    ResolvedOptions {
      bigs: self.bigs,
      border: self.border,
      color,
      color_scales: self.color_scales,
      digits: self.digits,
      footer: self.footer,
      row_numbers: self.row_numbers,
      termbg,
      theme,
      title: self.title,
      vanilla: self.vanilla,
      width: match self.width {
        WidthMode::Auto => ResolvedWidth::Fixed(terminal_width()),
        WidthMode::Fixed(width) => ResolvedWidth::Fixed(width),
        WidthMode::Header => ResolvedWidth::Header,
        WidthMode::Natural => ResolvedWidth::Natural,
      },
      zebra: self.zebra,
    }
  }
}

#[repr(u8)]
#[derive(Clone, Copy, Debug, Default, Eq, Ord, PartialEq, PartialOrd)]
pub enum ColumnBig {
  #[default]
  Normal = 0,
  Big = 1,
  Bigger = 2,
  Biggest = 3,
}

impl ColumnBig {
  pub fn operation(self) -> Option<ColumnOperation> {
    match self {
      Self::Normal => None,
      Self::Big => Some(ColumnOperation::Big),
      Self::Bigger => Some(ColumnOperation::Bigger),
      Self::Biggest => Some(ColumnOperation::Biggest),
    }
  }
}

/// Table border styles.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum Border {
  AsciiRounded,
  Basic,
  BasicCompact,
  Compact,
  CompactDouble,
  Dots,
  Double,
  Heavy,
  Light,
  Markdown,
  None,
  Psql,
  Reinforced,
  Restructured,
  #[default]
  Rounded,
  Single,
  Thin,
  WithLove,
}

/// Should Tennis use color?
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum ColorMode {
  #[default]
  Auto,
  On,
  Off,
}

/// Dark versus light color theme.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum ThemeMode {
  #[default]
  Auto,
  Dark,
  Light,
}

/// How Tennis chooses the table width.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum WidthMode {
  #[default]
  Auto,
  Fixed(usize),
  Header,
  Natural,
}
