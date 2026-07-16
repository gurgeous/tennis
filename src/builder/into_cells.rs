//! Row-ish values we can turn into cell strings.

/// Converts headers or one row of cells into strings.
pub trait IntoCells {
  /// Returns one string per cell, in display order.
  fn into_cells(self) -> Vec<String>;
}

impl<T> IntoCells for Vec<T>
where
  T: ToString,
{
  fn into_cells(self) -> Vec<String> {
    self.into_iter().map(|value| value.to_string()).collect()
  }
}

impl<T, const N: usize> IntoCells for [T; N]
where
  T: ToString,
{
  fn into_cells(self) -> Vec<String> {
    self.into_iter().map(|value| value.to_string()).collect()
  }
}

impl<T> IntoCells for &[T]
where
  T: ToString,
{
  fn into_cells(self) -> Vec<String> {
    self.iter().map(ToString::to_string).collect()
  }
}

macro_rules! impl_tuple_row {
  ($($name:ident:$index:tt),+) => {
    impl<$($name),+> IntoCells for ($($name,)+)
    where
      $($name: ToString,)+
    {
      fn into_cells(self) -> Vec<String> {
        vec![$(self.$index.to_string(),)+]
      }
    }
  };
}

// Tuples work as lightweight rows up to arity 12.
impl_tuple_row!(A:0, B:1);
impl_tuple_row!(A:0, B:1, C:2);
impl_tuple_row!(A:0, B:1, C:2, D:3);
impl_tuple_row!(A:0, B:1, C:2, D:3, E:4);
impl_tuple_row!(A:0, B:1, C:2, D:3, E:4, F:5);
impl_tuple_row!(A:0, B:1, C:2, D:3, E:4, F:5, G:6);
impl_tuple_row!(A:0, B:1, C:2, D:3, E:4, F:5, G:6, H:7);
impl_tuple_row!(A:0, B:1, C:2, D:3, E:4, F:5, G:6, H:7, I:8);
impl_tuple_row!(A:0, B:1, C:2, D:3, E:4, F:5, G:6, H:7, I:8, J:9);
impl_tuple_row!(A:0, B:1, C:2, D:3, E:4, F:5, G:6, H:7, I:8, J:9, K:10);
impl_tuple_row!(A:0, B:1, C:2, D:3, E:4, F:5, G:6, H:7, I:8, J:9, K:10, L:11);

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_borrowed_slice_into_cells() {
    let values = ["name", "score"];
    assert_eq!(vec!["name".to_owned(), "score".to_owned()], values.as_slice().into_cells());
  }
}
