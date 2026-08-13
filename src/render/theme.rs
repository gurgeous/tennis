//! ANSI color styles for table chrome, headers, cells, numerics.

use anstyle::{Ansi256Color, Color as AnsiColor, RgbColor};

use super::{
  ansi256::Ansi256,
  resolved::{ResolvedOptions, ResolvedTheme},
};

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
  pub(crate) fn new(options: &ResolvedOptions) -> Self {
    match options.theme {
      ResolvedTheme::Light => Self::light(options.termbg),
      ResolvedTheme::Dark => Self::dark(options.termbg),
    }
  }

  /// dark theme
  fn dark(termbg: Option<RgbColor>) -> Self {
    Self {
      chrome: fg(Ansi256::Gray12),
      cell: fg(Ansi256::Gray23),
      zebra: fg(Ansi256::White),
      zebra_bg: zebra_bg(termbg, RgbColor(255, 255, 255), DARK_ZEBRA_BLEND, Ansi256::Gray4),
      title: fg(Ansi256::Bluejeans),
      headers: vec![
        fg(Ansi256::Strawberry),
        fg(Ansi256::Coral),
        fg(Ansi256::Lightgoldenrod),
        fg(Ansi256::Wasabi),
        fg(Ansi256::Skyblue),
        fg(Ansi256::Melrose),
      ],
    }
  }

  /// light theme
  fn light(termbg: Option<RgbColor>) -> Self {
    Self {
      chrome: fg(Ansi256::Gray12),
      cell: fg(Ansi256::Gray4),
      zebra: fg(Ansi256::Black),
      zebra_bg: zebra_bg(termbg, RgbColor(0, 0, 0), LIGHT_ZEBRA_BLEND, Ansi256::Gray23),
      title: fg(Ansi256::Royalblue),
      headers: vec![
        fg(Ansi256::Tomato),
        fg(Ansi256::Coppertan),
        fg(Ansi256::Equator),
        fg(Ansi256::Asparagus),
        fg(Ansi256::Flyway),
        fg(Ansi256::Ube),
      ],
    }
  }
}

// helper for getting fg escape codes
fn fg(color: Ansi256) -> String {
  anstyle::Style::new().fg_color(Some(Ansi256Color(color.index()).into())).render().to_string()
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
fn zebra_bg(termbg: Option<RgbColor>, toward: RgbColor, amount: f64, fallback: Ansi256) -> String {
  let color = match termbg {
    Some(termbg) => AnsiColor::Rgb(blend_rgb(termbg, toward, amount)),
    None => AnsiColor::Ansi256(Ansi256Color(fallback.index())),
  };
  bg(color)
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::render::options::{ColorMode, RenderOptions, ThemeMode};

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
    let options = RenderOptions { color: Some(ColorMode::On), theme: ThemeMode::Dark, ..RenderOptions::default() };

    let theme = Theme::new(&options.resolve());
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
    let options = RenderOptions { color: Some(ColorMode::On), theme: ThemeMode::Light, ..RenderOptions::default() };

    let theme = Theme::new(&options.resolve());
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
    let options = RenderOptions { color: Some(ColorMode::On), theme: ThemeMode::Auto, ..RenderOptions::default() };

    let theme = Theme::new(&options.resolve());
    assert!(theme.chrome.starts_with('\x1b'));
  }

  #[test]
  fn test_theme_uses_detected_zebra_background() {
    for (mode, background, expected) in [
      (ThemeMode::Dark, RgbColor(48, 52, 70), "\x1b[48;2;69;72;89m"),
      (ThemeMode::Light, RgbColor(255, 255, 255), "\x1b[48;2;217;217;217m"),
    ] {
      let options = RenderOptions { color: Some(ColorMode::On), theme: mode, ..RenderOptions::default() };
      let mut resolved = options.resolve();
      resolved.termbg = Some(background);

      assert_eq!(expected, Theme::new(&resolved).zebra_bg);
    }
  }
}
