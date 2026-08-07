//! ANSI color styles for table chrome, headers, cells, numerics.

use anstyle::{Ansi256Color, Color as AnsiColor, RgbColor};

use crate::{
  resolved::{Resolved, ResolvedTheme},
  termbg::{Rgb, blend_tenth},
};

pub(crate) const RESET: &str = "\x1b[0m";
pub(crate) const BOLD: &str = "\x1b[1m";

#[derive(Clone, Debug)]
pub(crate) struct Theme {
  pub(crate) cell: Ansi,         // cell fg
  pub(crate) chrome: Ansi,       // borders, seps, placeholders, row num, footer
  pub(crate) headers: Vec<Ansi>, // header colors
  pub(crate) title: Ansi,        // title
  pub(crate) zebra: Ansi,        // zebra fg
  pub(crate) zebra_bg: Ansi,     // zebra bg
}

pub(crate) type Ansi = String;

impl Default for Theme {
  fn default() -> Self {
    Self::dark(None)
  }
}

impl Theme {
  pub(crate) fn new(options: &Resolved) -> Self {
    match options.theme {
      ResolvedTheme::Light => Self::light(options.terminal_bg),
      ResolvedTheme::Dark => Self::dark(options.terminal_bg),
    }
  }

  /// dark theme
  fn dark(background: Option<Rgb>) -> Self {
    Self {
      chrome: fg(243),
      cell: fg(254),
      zebra: fg(231),
      zebra_bg: zebra_bg(background, Rgb(255, 255, 255), 235),
      title: fg(75),
      headers: vec![fg(204), fg(209), fg(221), fg(150), fg(116), fg(147)],
    }
  }

  /// light theme
  fn light(background: Option<Rgb>) -> Self {
    Self {
      chrome: fg(243),
      cell: fg(235),
      zebra: fg(16),
      zebra_bg: zebra_bg(background, Rgb(0, 0, 0), 254),
      title: fg(26),
      headers: vec![fg(203), fg(173), fg(179), fg(107), fg(74), fg(104)],
    }
  }
}

// helper for getting fg escape codes
fn fg(color: u8) -> String {
  anstyle::Style::new().fg_color(Some(AnsiColor::Ansi256(Ansi256Color(color)))).render().to_string()
}

fn zebra_bg(background: Option<Rgb>, toward: Rgb, fallback: u8) -> String {
  let color = match background {
    Some(background) => {
      let Rgb(r, g, b) = blend_tenth(background, toward);
      AnsiColor::Rgb(RgbColor(r, g, b))
    }
    None => AnsiColor::Ansi256(Ansi256Color(fallback)),
  };
  anstyle::Style::new().bg_color(Some(color)).render().to_string()
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
    assert_eq!("\x1b[38;5;231m", theme.zebra);
    assert_eq!("\x1b[48;5;235m", theme.zebra_bg);
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
    assert_eq!("\x1b[38;5;16m", theme.zebra);
    assert_eq!("\x1b[48;5;254m", theme.zebra_bg);
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

  #[test]
  fn test_theme_uses_detected_zebra_background() {
    for (mode, background, expected) in [
      (ThemeMode::Dark, Rgb(48, 52, 70), "\x1b[48;2;69;72;89m"),
      (ThemeMode::Light, Rgb(255, 255, 255), "\x1b[48;2;230;230;230m"),
    ] {
      let options = Options { color: Some(ColorMode::On), theme: Some(mode), ..Options::default() };
      let mut resolved = Resolved::new(options);
      resolved.terminal_bg = Some(background);

      assert_eq!(expected, Theme::new(&resolved).zebra_bg);
    }
  }
}
