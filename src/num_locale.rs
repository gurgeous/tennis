//! Numeric locale settings.

use std::{env, sync::LazyLock};

use num_format::{Buffer, Locale};

static CURRENT: LazyLock<NumLocale> = LazyLock::new(NumLocale::load);

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NumLocale(Locale);

impl NumLocale {
  /// Returns the process locale captured on first use.
  pub fn current() -> &'static Self {
    &CURRENT
  }

  /// Formats an integer with locale grouping.
  pub fn format_int(&self, value: i64) -> String {
    let mut buffer = Buffer::default();
    buffer.write_formatted(&value, &self.0);
    buffer.as_str().to_owned()
  }

  /// Rounds to a fixed precision, then localizes separators.
  pub fn format_float(&self, value: f64, digits: usize) -> String {
    let rounded = format!("{value:.digits$}");
    let (whole, frac) = rounded.split_once('.').unwrap_or((rounded.as_str(), ""));
    let suffix_len = if digits > 0 { self.0.decimal().len() + frac.len() } else { 0 };
    let mut out = whole.parse::<i64>().map_or_else(
      |_| whole.to_owned(),
      |whole| {
        let mut buffer = Buffer::default();
        buffer.write_formatted(&whole, &self.0);
        let mut out = String::with_capacity(buffer.as_str().len() + suffix_len);
        out.push_str(buffer.as_str());
        out
      },
    );
    if digits > 0 {
      out.push_str(self.0.decimal());
      out.push_str(frac);
    }
    out
  }

  pub fn format_percent(&self, value: f64, digits: usize) -> String {
    format!("{}%", self.format_float(value, digits))
  }

  // POSIX precedence for the numeric locale.
  fn load() -> Self {
    let name =
      ["LC_ALL", "LC_NUMERIC", "LANG"].into_iter().find_map(|key| env::var(key).ok().filter(|s| !s.is_empty()));
    Self::from_name(name.as_deref())
  }

  fn from_name(name: Option<&str>) -> Self {
    let Some(name) = name else {
      return Self(Locale::en_US_POSIX);
    };
    // num-format uses CLDR names such as en_US, without POSIX encodings or modifiers.
    let name = name.split(['.', '@']).next().unwrap_or(name).replace('-', "_");
    if matches!(name.as_str(), "C" | "POSIX") {
      return Self(Locale::en_US_POSIX);
    }
    let locale = Locale::from_name(&name)
      .or_else(|_| Locale::from_name(name.split('_').next().unwrap_or("en")))
      .unwrap_or(Locale::en);
    Self(locale)
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_from_name() {
    for (name, locale) in [
      (Some("en_US.UTF-8"), Locale::en),
      (Some("de-DE"), Locale::de),
      (Some("C.UTF-8"), Locale::en_US_POSIX),
      (None, Locale::en_US_POSIX),
    ] {
      assert_eq!(NumLocale(locale), NumLocale::from_name(name));
    }
  }

  #[test]
  fn test_format() {
    let locale = NumLocale::from_name(Some("en_US"));
    for (formatted, actual) in [
      ("-1,234", locale.format_int(-1234)),
      ("1,234.57", locale.format_float(1234.567, 2)),
      ("1,000", locale.format_float(999.6, 0)),
      ("2.000", locale.format_float(1.9999, 3)),
      ("10.0", locale.format_float(9.99, 1)),
      ("0.000", locale.format_float(-0.0001, 3)),
      ("12.5%", locale.format_percent(12.5, 1)),
    ] {
      assert_eq!(formatted, actual);
    }
  }

  #[test]
  fn test_format_locale() {
    assert_eq!("1.234,57", NumLocale::from_name(Some("de_DE")).format_float(1234.567, 2));
    assert_eq!("1234.57", NumLocale::from_name(Some("C")).format_float(1234.567, 2));
    assert_eq!("1,23,45,678.90", NumLocale::from_name(Some("en_IN")).format_float(12345678.9, 2));
  }
}
