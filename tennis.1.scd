tennis(1)

# NAME

tennis - print stylish CSV tables in your terminal

# SYNOPSIS

*tennis* [_options..._] <file.csv>

# DESCRIPTION

*tennis* is a small CLI for printing stylish CSV tables in your terminal.
Rows will be truncated to fit and it'll automatically pick nice colors
to match your terminal. Written in Zig.

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

# OPTIONS

*-n*, *--row-numbers*
	Show row numbers.

*-t*, *--title* <string>
	Add a title above the table.

*-w*, *--width* <int>
	Set the maximum table width in characters. By default, *tennis* uses the
	current terminal width or *80* if it can't be detected.

*--color* <color>
	Control color output. Valid values: *on*, *off*, *auto*. The default is
	*on*. Also honors *NO_COLOR* and *FORCE_COLOR*.

*--digits* <int>
	Set the number of digits after the decimal for float columns. Valid values:
	*1* through *6*. The default is *3*.

*--theme* <theme>
	Select the color theme. Valid values: *auto*, *dark*, *light*. The default
	is *auto*.

*--vanilla*
	Disable type inference and numeric formatting.

# EXAMPLES

Render with row numbers and a title:

	$ tennis --row-numbers --title Diamonds diamonds.csv

Read from standard input:

	$ cat diamonds.csv | tennis

Disable colors and numeric formatting:

	$ tennis --color off --vanilla diamonds.csv

# SOURCE

https://github.com/gurgeous/tennis

# SEE ALSO

*column*(1), *awk*(1), *cut*(1), *sort*(1)
