//! Public types used in builder/options/etc

/// Table border styles.
#[non_exhaustive]
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

/// Should we use color?
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum ColorMode {
  #[default]
  Auto,
  On,
  Off,
}

impl From<bool> for ColorMode {
  fn from(on: bool) -> Self {
    if on { Self::On } else { Self::Off }
  }
}

/// Dark vs light color theme.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum ThemeMode {
  #[default]
  Auto,
  Dark,
  Light,
}

/// How do we choose table width?
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum WidthMode {
  #[default]
  Auto,
  Fixed(usize),
  Header,
  Natural,
}

impl From<usize> for WidthMode {
  fn from(width: usize) -> Self {
    Self::Fixed(width)
  }
}
