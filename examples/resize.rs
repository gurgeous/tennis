//! Redraws a CSV table when the terminal width changes.

use std::{
  io::{self, Write},
  sync::atomic::{AtomicBool, Ordering},
  thread,
  time::Duration,
};

use tennis::{ColorMode, Grid, Table, ThemeMode};
use terminal_size::{Height, Width};

const CSV: &str = include_str!("../tests/titanic.csv");
static INTERRUPTED: AtomicBool = AtomicBool::new(false);

fn main() -> Result<(), Box<dyn std::error::Error>> {
  install_signal_handlers();

  let _terminal = TerminalGuard::enter()?;
  let grid = load_csv()?;
  let mut last_size = None;
  let mut stdout = io::stdout().lock();

  while !INTERRUPTED.load(Ordering::Relaxed) {
    let size = terminal_size::terminal_size_of(io::stdout()).map(|(Width(w), Height(h))| (w, h));
    if size != last_size {
      last_size = size;
      redraw(&mut stdout, &grid)?;
    }
    thread::sleep(Duration::from_millis(20));
  }

  Ok(())
}

fn load_csv() -> Result<Grid, Box<dyn std::error::Error>> {
  let mut reader = csv::Reader::from_reader(CSV.as_bytes());
  let headers = reader.headers()?.iter().map(str::to_owned).collect();
  let rows = reader
    .records()
    .take(25)
    .map(|record| record.map(|record| record.iter().map(str::to_owned).collect()))
    .collect::<Result<Vec<Vec<String>>, csv::Error>>()?;

  Ok(Grid::new(headers, rows)?)
}

//
// resize
//

fn redraw(out: &mut impl Write, grid: &Grid) -> Result<(), Box<dyn std::error::Error>> {
  let table = Table::builder()
    .load_grid(grid.clone())
    .title("Titanic")
    .color(ColorMode::On)
    .theme(ThemeMode::Dark)
    .deselect(["PassengerId", "Survived", "Pclass"])
    .build()?;

  let mut frame = String::new();
  frame.push_str("\x1b[2J\x1b[H"); // clear / scrollback / home
  frame.push_str(&table.into_text());
  out.write_all(frame.as_bytes())?;
  out.flush()?;
  Ok(())
}

//
// terminal guard
//

struct TerminalGuard;

impl TerminalGuard {
  fn enter() -> io::Result<Self> {
    let mut stdout = io::stdout().lock();
    stdout.write_all(b"\x1b[?7l\x1b[?25l")?; // disable autowrap / hide cursor
    stdout.flush()?;
    Ok(Self)
  }
}

impl Drop for TerminalGuard {
  fn drop(&mut self) {
    let mut stdout = io::stdout().lock();
    let _ = stdout.write_all(b"\x1b[?7h\x1b[?25h"); // restore autowrap / cursor
    let _ = stdout.flush();
  }
}

//
// signals
//

#[cfg(unix)]
fn install_signal_handlers() {
  unsafe extern "C" {
    fn signal(signum: i32, handler: extern "C" fn(i32)) -> extern "C" fn(i32);
  }

  extern "C" fn handle_sigint(_: i32) {
    INTERRUPTED.store(true, Ordering::Relaxed);
  }

  const SIGINT: i32 = 2;

  // SAFETY: the handler only writes to an AtomicBool, which is signal-safe.
  unsafe {
    signal(SIGINT, handle_sigint);
  }
}

#[cfg(not(unix))]
fn install_signal_handlers() {}
