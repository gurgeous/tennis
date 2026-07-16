//! Demonstrates deriving Record for typed rows.

// setup tennis via derive
#[derive(tennis::Record)]
#[tennis(
  title = "Diamonds",
  footer = "inline rows from tests/test.csv",
  border = "rounded",
  digits = 2,
  row_numbers = true,
  titleize,
  zebra
)]
struct Diamond {
  #[tennis(rename = "carrot", scale = "green_red")]
  carat: f64,
  cut: &'static str,
  color: &'static str,
  clarity: &'static str,
  depth: f64,
  table: u32,
  price: u32,
  x: f64,
  y: f64,
  z: f64,
  #[tennis(skip)]
  _id: &'static str,
}

fn main() {
  // sample data
  #[rustfmt::skip]
  let diamonds = [
    Diamond { carat: 0.23, cut: "Ideal", color: "E", clarity: "SI2", depth: 61.5, table: 55, price: 326, x: 3.95, y: 3.98, z: 2.43, _id: "dmd-0A23E" },
    Diamond { carat: 0.21, cut: "Premium", color: "E", clarity: "SI1", depth: 59.8, table: 61, price: 326, x: 3.89, y: 3.84, z: 2.31, _id: "dmd-0P21E" },
    Diamond { carat: 0.23, cut: "Good", color: "E", clarity: "VS1", depth: 56.9, table: 65, price: 327, x: 4.05, y: 4.07, z: 2.31, _id: "dmd-0G23E" },
    Diamond { carat: 0.29, cut: "Premium", color: "I", clarity: "VS2", depth: 62.4, table: 58, price: 334, x: 4.20, y: 4.23, z: 2.63, _id: "dmd-0P29I" },
    Diamond { carat: 0.31, cut: "Good", color: "J", clarity: "SI2", depth: 63.3, table: 58, price: 335, x: 4.34, y: 4.35, z: 2.75, _id: "dmd-0G31J" },
  ];

  // now print
  let table = tennis::Table::builder().load_records(diamonds).build().expect("no");
  print!("{}", table.into_text());
}
