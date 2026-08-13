//! Render settings.

use super::{
  color_scale::ColorScale,
  resolved::{ResolvedOptions, ResolvedWidth, resolve_color, resolve_theme, terminal_width},
};
use crate::{
  error::{ColumnOperation, Error, Result},
  grid::Grid,
};

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct RenderOptions {
  pub(crate) bigs: Vec<(String, ColumnBig)>,
  pub(crate) border: Border,
  pub(crate) color: Option<ColorMode>,
  pub(crate) color_scales: Vec<(String, ColorScale)>,
  pub(crate) digits: usize,
  pub(crate) footer: Option<String>,
  pub(crate) row_numbers: bool,
  pub(crate) theme: ThemeMode,
  pub(crate) title: Option<String>,
  pub(crate) vanilla: bool,
  pub(crate) width: WidthMode,
  pub(crate) zebra: bool,
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
      theme: ThemeMode::Auto,
      title: None,
      vanilla: false,
      width: WidthMode::Auto,
      zebra: false,
    }
  }
}

impl RenderOptions {
  pub(crate) fn validate(&self, grid: &Grid) -> Result<()> {
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

  pub(crate) fn resolve(self) -> ResolvedOptions {
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
pub(crate) enum ColumnBig {
  #[default]
  Normal = 0,
  Big = 1,
  Bigger = 2,
  Biggest = 3,
}

impl ColumnBig {
  pub(crate) fn operation(self) -> Option<ColumnOperation> {
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
pub(crate) enum Border {
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
pub(crate) enum ColorMode {
  #[default]
  Auto,
  On,
  Off,
}

/// Dark versus light color theme.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(crate) enum ThemeMode {
  #[default]
  Auto,
  Dark,
  Light,
}

/// How Tennis chooses the table width.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(crate) enum WidthMode {
  #[default]
  Auto,
  Fixed(usize),
  Header,
  Natural,
}
