//! ANSI color styles for table chrome, headers, cells, numerics.

use anstyle::{Ansi256Color, Color as AnsiColor};

use crate::resolved::{Resolved, ResolvedTheme};

pub(crate) const RESET: &str = "\x1b[0m";
pub(crate) const BOLD: &str = "\x1b[1m";

#[derive(Clone, Debug)]
pub(crate) struct Theme {
  pub(crate) cell: Ansi,         // cell fg
  pub(crate) chrome: Ansi,       // borders, seps, placeholders, row num, footer
  pub(crate) headers: Vec<Ansi>, // header colors
  pub(crate) title: Ansi,        // title
  pub(crate) zebra: Ansi,        // zebra fg+gb
}

pub(crate) type Ansi = String;

impl Default for Theme {
  fn default() -> Self {
    Self::dark()
  }
}

impl Theme {
  pub(crate) fn new(options: &Resolved) -> Self {
    match options.theme {
      ResolvedTheme::Light => Self::light(),
      ResolvedTheme::Dark => Self::dark(),
    }
  }

  /// dark theme
  fn dark() -> Self {
    Self {
      chrome: fg(243),
      cell: fg(254),
      zebra: fg_bg(231, 235),
      title: fg(75),
      headers: vec![fg(204), fg(209), fg(221), fg(150), fg(116), fg(147)],
    }
  }

  /// light theme
  fn light() -> Self {
    Self {
      chrome: fg(243),
      cell: fg(235),
      zebra: fg_bg(16, 254),
      title: fg(26),
      headers: vec![fg(203), fg(173), fg(179), fg(107), fg(74), fg(104)],
    }
  }
}

// helper for getting fg escape codes
fn fg(color: u8) -> String {
  anstyle::Style::new().fg_color(Some(AnsiColor::Ansi256(Ansi256Color(color)))).render().to_string()
}

// helper for getting fg+bg escape codes
fn fg_bg(fg: u8, bg: u8) -> String {
  anstyle::Style::new()
    .fg_color(Some(AnsiColor::Ansi256(Ansi256Color(fg))))
    .bg_color(Some(AnsiColor::Ansi256(Ansi256Color(bg))))
    .render()
    .to_string()
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::builder::{
    Options,
    types::{ColorMode, ThemeMode},
  };

  #[test]
  fn test_theme_dark() {
    let options = Options { color: Some(ColorMode::On), theme: Some(ThemeMode::Dark), ..Options::default() };

    let theme = Theme::new(&Resolved::new(options));
    assert!(theme.chrome.starts_with('\x1b'));
    assert!(theme.cell.starts_with('\x1b'));
    assert!(theme.zebra.starts_with('\x1b'));
    assert!(theme.title.starts_with('\x1b'));
    assert_eq!(6, theme.headers.len());
    assert!(theme.headers.iter().all(|code| code.starts_with('\x1b')));
  }

  #[test]
  fn test_theme_light() {
    let options = Options { color: Some(ColorMode::On), theme: Some(ThemeMode::Light), ..Options::default() };

    let theme = Theme::new(&Resolved::new(options));
    assert!(theme.chrome.starts_with('\x1b'));
    assert!(theme.cell.starts_with('\x1b'));
    assert!(theme.zebra.starts_with('\x1b'));
    assert!(theme.title.starts_with('\x1b'));
    assert_eq!(6, theme.headers.len());
    assert!(theme.headers.iter().all(|code| code.starts_with('\x1b')));
  }

  #[test]
  fn test_theme_resolves() {
    let options = Options { color: Some(ColorMode::On), theme: Some(ThemeMode::Auto), ..Options::default() };

    let theme = Theme::new(&Resolved::new(options));
    assert!(theme.chrome.starts_with('\x1b'));
  }
}
