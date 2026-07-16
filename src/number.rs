//! Numeric detection and formatting for string cell values.

//
// is_xxx - note these do NOT have to handle empty case
//

pub(crate) fn is_float(input: &str) -> bool {
  let rest = input.strip_prefix('-').unwrap_or(input);
  let Some((whole, fract)) = rest.split_once('.') else {
    return false;
  };
  is_digits(whole) && is_digits(fract)
}

pub(crate) fn is_int(input: &str) -> bool {
  let rest = input.strip_prefix('-').unwrap_or(input);
  is_digits(rest)
}

pub(crate) fn is_percent(input: &str) -> bool {
  let Some(rest) = input.strip_suffix('%') else {
    return false;
  };
  is_int(rest) || is_float(rest)
}

//
// format_xxx - note these do NOT have to handle empty case
//

pub fn format_float(input: &str, digits: usize) -> String {
  debug_assert!(is_int(input) || is_float(input), "format_float expects an int or float");
  Floater::new(input, digits).format()
}

pub fn format_int(input: &str) -> String {
  debug_assert!(is_int(input), "format_int expects an int");
  // fast path
  let (neg, digits) = input.strip_prefix('-').map_or((false, input), |digits| (true, digits));
  if !neg && input.len() <= 3 {
    return input.to_owned();
  }

  let mut out = String::with_capacity(8);
  if neg {
    out.push('-');
  }
  push_grouped_digits(&mut out, digits.as_bytes());
  out
}

//
// internal Floater helper
//

struct Floater {
  neg: bool,
  whole: Vec<u8>,
  fract: Vec<u8>,
}

impl Floater {
  fn new(input: &str, digits: usize) -> Self {
    // -?digits(.digits)?
    let (neg, input) = input.strip_prefix('-').map_or((false, input), |rest| (true, rest));
    let (whole, fract) = input.split_once('.').map_or((input, ""), |parts| parts);

    // round
    let mut whole = whole.as_bytes().to_vec();
    let fract_input = fract.as_bytes();
    let mut fract = fract_input[..fract_input.len().min(digits)].to_vec();
    if fract_input.get(digits).is_some_and(|b| *b >= b'5') && round_up_digits(&mut fract) {
      round_up_whole(&mut whole);
    }
    fract.resize(digits, b'0');

    // Render -0.000 as 0.000.
    let neg = neg && !(is_zero(&whole) && is_zero(&fract));
    Self { neg, whole, fract }
  }

  fn format(&self) -> String {
    let mut out = String::with_capacity(8);
    if self.neg {
      out.push('-');
    }
    push_grouped_digits(&mut out, &self.whole);
    if !self.fract.is_empty() {
      out.push('.');
      out.push_str(ascii_digits(&self.fract));
    }
    out
  }
}

//
// tiny helpers
//

fn is_zero(digits: &[u8]) -> bool {
  digits.iter().all(|b| *b == b'0')
}

fn push_grouped_digits(out: &mut String, digits: &[u8]) {
  let first = (digits.len() - 1) % 3 + 1;
  out.push_str(ascii_digits(&digits[..first]));

  for chunk in digits[first..].chunks(3) {
    out.push(',');
    out.push_str(ascii_digits(chunk));
  }
}

fn ascii_digits(digits: &[u8]) -> &str {
  std::str::from_utf8(digits).expect("decimal digits are valid UTF-8")
}

fn is_digits(input: &str) -> bool {
  !input.is_empty() && input.bytes().all(|b| b.is_ascii_digit())
}

fn round_up_digits(digits: &mut [u8]) -> bool {
  for digit in digits.iter_mut().rev() {
    if *digit != b'9' {
      *digit += 1;
      return false;
    }
    *digit = b'0';
  }
  true
}

fn round_up_whole(digits: &mut Vec<u8>) {
  if round_up_digits(digits) {
    digits.insert(0, b'1');
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_is_int() {
    for input in ["0", "123", "-123"] {
      assert!(is_int(input));
    }
    for input in ["", "-", "1.0", "+1", "1e6", "abc"] {
      assert!(!is_int(input));
    }
  }

  #[test]
  fn test_format_int() {
    assert_eq!("0", format_int("0"));
    assert_eq!("123", format_int("123"));
    assert_eq!("1,234", format_int("1234"));
    assert_eq!("123,456", format_int("123456"));
    assert_eq!("-1,234,567", format_int("-1234567"));
  }

  #[cfg(debug_assertions)]
  #[test]
  #[should_panic(expected = "format_int expects an int")]
  fn test_format_int_debug_asserts_precondition() {
    format_int("-");
  }

  #[test]
  fn test_is_float() {
    for input in ["1.0", "-1.0", "12.34"] {
      assert!(is_float(input));
    }
    for input in ["", "1", "1.", "1.0b", ".5", "-.5", "1e6", "+1.0"] {
      assert!(!is_float(input));
    }
  }

  #[test]
  fn test_is_percent() {
    assert!(is_percent("12%"));
    assert!(is_percent("-12.5%"));
    assert!(!is_percent("12"));
    assert!(!is_percent(".5%"));
  }

  #[test]
  fn test_format_float() {
    assert_eq!("4.000", format_float("4.0", 3));
    assert_eq!("1,234.000", format_float("1234.0", 3));
    assert_eq!("-1,234,567.891", format_float("-1234567.8912", 3));
    assert_eq!("1,000", format_float("999.6", 0));
    assert_eq!("0.000", format_float("0.0001", 3));
    assert_eq!("0.000", format_float("-0.0001", 3));
    assert_eq!("1.000", format_float("0.9999", 3));
    assert_eq!("2.000", format_float("1.9999", 3));
    assert_eq!("10.0", format_float("9.99", 1));
  }

  #[cfg(debug_assertions)]
  #[test]
  #[should_panic(expected = "format_float expects an int or float")]
  fn test_format_float_debug_asserts_precondition() {
    format_float("", 3);
  }

  #[test]
  fn test_format_float_handles_huge_values() {
    let huge = format!("{}.0", "9".repeat(400));
    assert!(is_float(&huge));
    assert_eq!(format!("{}.000", format_int(&"9".repeat(400))), format_float(&huge, 3));
  }

  #[test]
  fn test_format_float_ruby_tennis_cases() {
    assert_eq!("1,234.567", format_float("1234.567111", 3));
    assert_eq!("-1,234.567", format_float("-1234.567111", 3));
    assert_eq!("-1.123", format_float("-1.12345", 3));
    assert_eq!("1.100", format_float("1.1", 3));
    assert_eq!("0", format_float("0", 0));
    assert_eq!("0.1234", format_float("0.1234", 4));
    assert_eq!("-1,234.1234", format_float("-1234.1234", 4));
  }
}
