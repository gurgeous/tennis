tennis(1)

# NAME

tennis - print stylish CSV tables in your terminal

https://github.com/gurgeous/tennis

# SYNOPSIS

*tennis* [_options..._] <file.csv>

Also supports stdin, json/jsonl, sqlite, etc.

# DESCRIPTION

*tennis* is a small CLI for printing stylish CSV tables in your terminal.
Rows will be truncated to fit and it'll automatically pick nice colors
to match your terminal. Works with all *CSV* variants as well as
*JSON/JSONL* and *SQLite* files. Written in zig.

# DEMO

Render a CSV file:

```
$ tennis diamonds.csv
╭───────┬───────────┬───────┬─────────┬────────┬───────┬───────╮
│ carat │ cut       │ color │ clarity │ depth  │ table │ price │
├───────┼───────────┼───────┼─────────┼────────┼───────┼───────┤
│ 0.230 │ Ideal     │ E     │ SI2     │ 61.500 │    55 │   326 │
│ 0.210 │ Premium   │ E     │ SI1     │ 59.800 │    61 │   326 │
│ 0.230 │ Good      │ E     │ VS1     │ 56.900 │    65 │   327 │
│ 0.290 │ Premium   │ I     │ VS2     │ 62.400 │    58 │   334 │
│ 0.310 │ Good      │ J     │ SI2     │ 63.300 │    58 │   335 │
...
```

# POPULAR OPTIONS

*--border* <border>
	Select the table border style (see below). The default is *rounded*.

*--peek*
	Show the shape, some sample rows, and compact per-column stats.

*-n*, *--row-numbers*
	Show row numbers.

*-t*, *--title* <string>
	Add a title above the table.

*--zebra*
	Turn on zebra stripes.

# SORTING & FILTERING

*--filter* <string>
	Keep rows where any field contains the given text, case-insensitive.

*--deselect* <headers>
	De-select one or more comma-separated headers after any *--select*.

*--head* <int>
	Show the first _N_ data rows.

*-r*, *--reverse*
	Reverse row order. Helpful when sorting.

*--select* <headers>
	Select, reorder, or repeat one or more comma-separated headers.

*--shuffle*
	Shuffle rows.

*--sort* <headers>
	Sort rows by one or more comma-separated headers.

*--table* <name>
	Select a specific table from a sqlite file.

*--tail* <int>
	Show the last _N_ data rows.

# OTHER OPTIONS

*--color* <color>
	Control color output. Valid values: *on*, *off*, *auto*. The default is
	*on*. Also honors *NO_COLOR* and *FORCE_COLOR*.

*--delimiter* <char>
	Set the delimiter when reading input. Defaults to '*,*' naturally. It
	accepts any char, or *tab* for tab-delimited input. Note that tennis tries
	to automatically detect the correct delimiter, so hopefully this is
	rarely necessary.

*--digits* <int>
	Set the number of digits after the decimal for float columns. Valid values
	*1* through *6*, the default is *3*.

*--pager*
	Send output through *$PAGER* or *less*. If *LESS* is unset, it defaults to
	*FRX*.

*--theme* <theme>
	Select the color theme. Valid values: *auto*, *dark*, *light*. The default
	is *auto*.

*--vanilla*
	Disable type inference and numeric formatting.

*--width* <width>
	Set the width mode. Pass an integer for a maximum table width in
	characters, *min* for header-width columns, or *max* for the natural
	column widths. By default, *tennis* uses the current terminal width or
	*80* if it can't be detected.

# BORDERS

Border names are adapted from Nushell table themes, which in turn build on the
*tabled* crate:

*ascii_rounded*, *basic*, *basic_compact*, *compact*, *compact_double*,
*dots*, *double*, *heavy*, *light*, *markdown*, *none*, *psql*,
*reinforced*, *restructured*, *rounded*, *single*, *thin*, *with_love*

# EXAMPLES

Render with row numbers and a title:

	$ tennis --row-numbers --title Diamonds diamonds.csv # csv

Peek at shape, sample rows, and column stats:

	$ tennis --peek diamonds.csv

Render json, from standard input:

	$ cat diamonds.json | tennis

Show 20 random rows:

	$ tennis --shuffle --head 20 diamonds.csv

Select and reorder columns:

	$ tennis --select price,carat,cut diamonds.csv

Suppress a few columns:

	$ tennis --deselect x,y,z diamonds.csv

Only show "ideal" diamonds:

	$ tennis --filter ideal diamonds.csv

Render with a different border:

	$ tennis --border dots diamonds.csv

Page through a large table:

	$ tennis --pager diamonds.csv

# SIMILAR TOOLS

- *bat* - Syntax-highlighting pager that also works well for CSV files.
- *csvlens* - Terminal CSV viewer for browsing files interactively.
- *miller* - CSV/TSV/JSON processing and transformation.
- *nushell* - Modern shell with first-class structured table data.
- *qsv* - Fast CSV toolkit for filtering, joining, and summarizing data.
- *table_tennis* - Related table-rendering project that inspired this one.
- *tabiew* - Interactive terminal table viewer.
- *tidyviewer* - Colorful terminal viewer for delimited data.
- *Terminal::Table* - Ruby library for pretty-printing tabular data.
- *visidata* - Powerful terminal data exploration tool.

# SEE ALSO

*column*(1), *awk*(1), *cut*(1), *mlr*(1), *sort*(1)
