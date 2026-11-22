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
    // num-format only does ints, so group the whole part of |value| and add the sign back
    let rounded = format!("{:.digits$}", value.abs());
    let (whole, frac) = rounded.split_once('.').unwrap_or((rounded.as_str(), ""));
    let mut out = String::new();
    // -0.0001 rounds to 0.000, so it gets no sign
    if value < 0.0 && rounded.bytes().any(|b| matches!(b, b'1'..=b'9')) {
      out.push_str(self.0.minus_sign());
    }
    match whole.parse::<u64>() {
      Ok(whole) => {
        let mut buffer = Buffer::default();
        buffer.write_formatted(&whole, &self.0);
        out.push_str(buffer.as_str());
      }
      Err(_) => out.push_str(whole),
    }
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
      ("-0.500", locale.format_float(-0.5, 3)),
      ("-1,234.50", locale.format_float(-1234.5, 2)),
      ("-1", locale.format_float(-0.6, 0)),
      ("0.000", locale.format_float(-0.0, 3)),
      ("0", locale.format_float(-0.4, 0)),
      ("-1,000", locale.format_float(-999.6, 0)),
      ("-100000000000000000000.0", locale.format_float(-1e20, 1)),
      ("-0.1%", locale.format_percent(-0.06, 1)),
      ("0.0%", locale.format_percent(-0.04, 1)),
      ("12.5%", locale.format_percent(12.5, 1)),
    ] {
      assert_eq!(formatted, actual);
    }
  }

  #[test]
  fn test_format_locale() {
    let [de, c, en_in] = ["de_DE", "C", "en_IN"].map(|name| NumLocale::from_name(Some(name)));
    for (formatted, actual) in [
      ("1.234,57", de.format_float(1234.567, 2)),
      ("-0,5", de.format_float(-0.5, 1)),
      ("-1.234", de.format_int(-1234)),
      ("1234.57", c.format_float(1234.567, 2)),
      ("-1234.57", c.format_float(-1234.567, 2)),
      ("-1234", c.format_int(-1234)),
      ("1,23,45,678.90", en_in.format_float(12345678.9, 2)),
      ("-1,23,45,678.90", en_in.format_float(-12345678.9, 2)),
      ("-12,34,567", en_in.format_int(-1234567)),
    ] {
      assert_eq!(formatted, actual);
    }
  }
}
