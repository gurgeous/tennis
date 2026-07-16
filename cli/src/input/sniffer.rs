//
// Heuristic delimiter sniffer for small CSV/TSV samples.
//
// Overall approach:
// - try a tiny fixed set of candidate delimiters
// - scan the sample line by line
// - count cols for each delim, make sure the sample doesn't look jagged or weird
// - the winner is the delim that works with the sample and has the most cols
//

const CANDIDATES: &[u8] = b",\t;|";

/// look at the first few lines, what delim do we see?
pub fn sniff(sample: &str) -> Option<u8> {
  let lines = split_lines(sample);

  if lines.len() < 3 || lines.iter().any(|line| line.is_empty()) {
    return None;
  }

  let mut best_count = 0;
  let mut best_delimiter = None;
  for &delimiter in CANDIDATES {
    let count = count_columns(&lines, delimiter);
    if count > best_count {
      best_count = count;
      best_delimiter = Some(delimiter);
    }
  }
  best_delimiter
}

/// Split on LF and trim CR per line so mixed CRLF/LF samples still sniff.
/// Drop the final line because file samples are often cut mid-record.
fn split_lines(sample: &str) -> Vec<&str> {
  let mut lines: Vec<_> = sample.split('\n').take(11).map(|line| line.strip_suffix('\r').unwrap_or(line)).collect();
  lines.pop();
  lines
}

fn count_columns(lines: &[&str], delimiter: u8) -> usize {
  let mut expected = 0;
  for line in lines {
    let n = count_columns_for_line(line, delimiter);
    if expected == 0 {
      expected = n;
    }
    if n != expected {
      return 0;
    }
  }
  if expected < 2 { 0 } else { expected }
}

fn count_columns_for_line(line: &str, delimiter: u8) -> usize {
  let mut n = 1;
  let mut in_quotes = false;
  let mut iter = line.as_bytes().iter().peekable();
  while let Some(&ch) = iter.next() {
    if ch == b'"' {
      if in_quotes && iter.peek() == Some(&&b'"') {
        iter.next();
      } else {
        in_quotes = !in_quotes;
      }
    } else if !in_quotes && ch == delimiter {
      n += 1;
    }
  }
  n
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_sniff_success() {
    let cases = [
      ("a,b,c\n1,2,3\n4,5,6\n7,8", b','),
      ("a;b;c\n1;2;3\n4;5;6\n7;8", b';'),
      ("a\tb\tc\n1\t2\t3\n4\t5\t6\n7\t8", b'\t'),
      ("a|b|c\n1|2|3\n4|5|6\n7|8", b'|'),
      ("a,b,c\n\"x,y\",2,3\n\"p,q\",5,6\n\"tail", b','),
      ("a,b,c\r\n1,2,3\r\n4,5,6\r\n7,8", b','),
      ("a,b,c\r\n1,2,3\n4,5,6\n7,8", b','),
      ("a,b,c,d;|\n1,2,3,4;|\n5,6,7,8;|\n9,10,11,", b','),
      ("a;b;c;d,|\n1;2;3;4,|\n5;6;7;8,|\n9;10;11;", b';'),
      ("a\tb\tc\td,|\n1\t2\t3\t4,|\n5\t6\t7\t8,|\n9\t10\t11\t", b'\t'),
      ("a|b|c|d,;\n1|2|3|4,;\n5|6|7|8,;\n9|10|11|", b'|'),
    ];
    for (sample, delimiter) in cases {
      assert_eq!(Some(delimiter), sniff(sample));
    }
  }

  #[test]
  fn test_sniff_none() {
    for sample in [
      "",
      "a;b\n\n1;2\n",
      "a,b\n1,2\n",
      "hello\nworld\n",
      "a,b,c\n1,2\n",
      "abcdef",
      "a,b,c\n1,2,3",
      "\"a,b,c\n1,2,3\n4,5,6\n",
    ] {
      assert_eq!(None, sniff(sample));
    }
  }

  #[test]
  fn test_sniff_priority() {
    assert_eq!(Some(b';'), sniff("a;b|c\n1;2|3\n4;5|6\n"));
  }

  #[test]
  fn test_split_lines() {
    let cases = [
      ("", Vec::<&str>::new()),
      ("a,b,c", vec![]),
      ("a,b,c\n1,2,3", vec!["a,b,c"]),
      ("a,b,c\n1,2,3\n4,5", vec!["a,b,c", "1,2,3"]),
      ("a,b,c\r\n1,2,3\r\n4,5", vec!["a,b,c", "1,2,3"]),
      ("a,b,c\r\n1,2,3\n4,5", vec!["a,b,c", "1,2,3"]),
      ("1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12", vec!["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]),
    ];

    for (sample, want) in cases {
      assert_eq!(want, split_lines(sample));
    }
  }

  #[test]
  fn test_count_columns_for_line() {
    let cases = [
      ("", b',', 1),
      ("a,b,c", b',', 3),
      ("\"a,b\",c", b',', 2),
      ("\"a\"\"b\",c", b',', 2),
      ("\"a,b,c", b',', 1),
      ("a|b|c", b'|', 3),
    ];

    for (line, delimiter, want) in cases {
      assert_eq!(want, count_columns_for_line(line, delimiter));
    }
  }
}
