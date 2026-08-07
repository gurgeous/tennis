//! Terminal background colors.

#[cfg(not(test))]
use std::time::Duration;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct Rgb(pub(crate) u8, pub(crate) u8, pub(crate) u8);

#[cfg(not(test))]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Mode {
  Dark,
  Light,
}

#[cfg(not(test))]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct Detected {
  pub(crate) background: Rgb,
  pub(crate) mode: Mode,
}

#[cfg(not(test))]
pub(crate) fn detect() -> Option<Detected> {
  let mut options = terminal_colorsaurus::QueryOptions::default();
  options.timeout = Duration::from_millis(200);
  crate::verbose::log(format_args!("termbg.detect() start"));
  let result = terminal_colorsaurus::color_palette(options);
  crate::verbose::log(format_args!("termbg.detect() => {result:?}"));
  let palette = result.ok()?;
  let mode = match palette.theme_mode() {
    terminal_colorsaurus::ThemeMode::Dark => Mode::Dark,
    terminal_colorsaurus::ThemeMode::Light => Mode::Light,
  };
  let (r, g, b) = palette.background.scale_to_8bit();
  Some(Detected { background: Rgb(r, g, b), mode })
}

// Move 10% toward another color, rounded to the nearest channel value.
pub(crate) fn blend_tenth(from: Rgb, toward: Rgb) -> Rgb {
  fn blend(from: u8, toward: u8) -> u8 {
    ((u16::from(from) * 9 + u16::from(toward) + 5) / 10) as u8
  }

  Rgb(blend(from.0, toward.0), blend(from.1, toward.1), blend(from.2, toward.2))
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_blend_tenth() {
    for (from, toward, expected) in [
      (Rgb(0, 0, 0), Rgb(255, 255, 255), Rgb(26, 26, 26)),
      (Rgb(255, 255, 255), Rgb(255, 255, 255), Rgb(255, 255, 255)),
      (Rgb(255, 255, 255), Rgb(0, 0, 0), Rgb(230, 230, 230)),
      (Rgb(128, 128, 128), Rgb(255, 255, 255), Rgb(141, 141, 141)),
      (Rgb(48, 52, 70), Rgb(255, 255, 255), Rgb(69, 72, 89)),
    ] {
      assert_eq!(expected, blend_tenth(from, toward));
    }
  }
}
