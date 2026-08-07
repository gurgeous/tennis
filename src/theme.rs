//! ANSI color styles for table chrome, headers, cells, numerics.

use anstyle::{Ansi256Color, Color as AnsiColor, RgbColor};

use crate::resolved::{Resolved, ResolvedTheme};

pub(crate) const RESET: &str = "\x1b[0m";
pub(crate) const BOLD: &str = "\x1b[1m";

const DARK_ZEBRA_BLEND: f64 = 0.10; // 10% lighter vs bg
const LIGHT_ZEBRA_BLEND: f64 = 0.15; // 15% darker vs bg

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
      ResolvedTheme::Light => Self::light(options.termbg),
      ResolvedTheme::Dark => Self::dark(options.termbg),
    }
  }

  /// dark theme
  fn dark(termbg: Option<RgbColor>) -> Self {
    Self {
      chrome: fg(243),
      cell: fg(254),
      zebra: fg(231),
      zebra_bg: zebra_bg(termbg, RgbColor(255, 255, 255), DARK_ZEBRA_BLEND, 235),
      title: fg(75),
      headers: vec![fg(204), fg(209), fg(221), fg(150), fg(116), fg(147)],
    }
  }

  /// light theme
  fn light(termbg: Option<RgbColor>) -> Self {
    Self {
      chrome: fg(243),
      cell: fg(235),
      zebra: fg(16),
      zebra_bg: zebra_bg(termbg, RgbColor(0, 0, 0), LIGHT_ZEBRA_BLEND, 254),
      title: fg(26),
      headers: vec![fg(203), fg(173), fg(179), fg(107), fg(74), fg(104)],
    }
  }
}

// helper for getting fg escape codes
fn fg(color: impl Into<AnsiColor>) -> String {
  anstyle::Style::new().fg_color(Some(color.into())).render().to_string()
}

// helper for getting bg escape codes
fn bg(color: impl Into<AnsiColor>) -> String {
  anstyle::Style::new().bg_color(Some(color.into())).render().to_string()
}

// blend (interpolate) two colors
fn blend_rgb(from: RgbColor, toward: RgbColor, amount: f64) -> RgbColor {
  RgbColor(lerp(from.0, toward.0, amount), lerp(from.1, toward.1, amount), lerp(from.2, toward.2, amount))
}

// lerp between two values
fn lerp(from: u8, toward: u8, amount: f64) -> u8 {
  (from as f64 + (toward as f64 - from as f64) * amount).round() as u8
}

// calculate zebra_bg from term background, use fallback if we don't know the term bg
fn zebra_bg(termbg: Option<RgbColor>, toward: RgbColor, amount: f64, fallback: u8) -> String {
  let color = match termbg {
    Some(termbg) => {
      let RgbColor(r, g, b) = blend_rgb(termbg, toward, amount);
      AnsiColor::Rgb(RgbColor(r, g, b))
    }
    None => AnsiColor::Ansi256(Ansi256Color(fallback)),
  };
  bg(color)
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::builder::{
    Options,
    types::{ColorMode, ThemeMode},
  };

  #[test]
  fn test_blend_rgb() {
    for (from, toward, amount, expected) in [
      (RgbColor(0, 0, 0), RgbColor(255, 255, 255), 0.10, RgbColor(26, 26, 26)),
      (RgbColor(255, 255, 255), RgbColor(255, 255, 255), 0.10, RgbColor(255, 255, 255)),
      (RgbColor(255, 255, 255), RgbColor(0, 0, 0), 0.15, RgbColor(217, 217, 217)),
      (RgbColor(128, 128, 128), RgbColor(255, 255, 255), 0.10, RgbColor(141, 141, 141)),
      (RgbColor(48, 52, 70), RgbColor(255, 255, 255), 0.10, RgbColor(69, 72, 89)),
    ] {
      assert_eq!(expected, blend_rgb(from, toward, amount));
    }
  }

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
      (ThemeMode::Dark, RgbColor(48, 52, 70), "\x1b[48;2;69;72;89m"),
      (ThemeMode::Light, RgbColor(255, 255, 255), "\x1b[48;2;217;217;217m"),
    ] {
      let options = Options { color: Some(ColorMode::On), theme: Some(mode), ..Options::default() };
      let mut resolved = Resolved::new(options);
      resolved.termbg = Some(background);

      assert_eq!(expected, Theme::new(&resolved).zebra_bg);
    }
  }
}
