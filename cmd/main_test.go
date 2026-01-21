package main

import (
	"testing"
)

func TestMain0(t *testing.T) {
	// no args (help)
	// invalid arg (exit 1)

	// tests := []struct {
	// 	name       string
	// 	args       []string
	// 	csvData    string
	// 	wantExit   int
	// 	wantOutput string
	// }{
	// 	{
	// 		name:       "valid csv file",
	// 		args:       []string{"tennis", "test.csv"},
	// 		csvData:    "Name,Score\nAlice,100\nBob,200\n",
	// 		wantExit:   -1, // no exit called
	// 		wantOutput: "", // would contain table output
	// 	},
	// 	{
	// 		name:       "invalid file",
	// 		args:       []string{"tennis", "nonexistent.csv"},
	// 		csvData:    "",
	// 		wantExit:   1,
	// 		wantOutput: "",
	// 	},
	// }

	// for _, tt := range tests {
	// 	t.Run(tt.name, func(t *testing.T) {
	// 		// Create temp file with test data if needed
	// 		if tt.csvData != "" {
	// 			tmpfile, err := os.CreateTemp("", "test*.csv")
	// 			assert.NoError(t, err)
	// 			defer os.Remove(tmpfile.Name())

	// 			_, err = tmpfile.Write([]byte(tt.csvData))
	// 			assert.NoError(t, err)
	// 			tmpfile.Close()

	// 			// Update args with temp filename
	// 			if len(tt.args) > 1 {
	// 				tt.args[1] = tmpfile.Name()
	// 			}
	// 		}

	// 		// Capture exit code
	// 		exitCode := -1
	// 		mockExit := func(code int) {
	// 			exitCode = code
	// 		}

	// 		// Capture output
	// 		var output bytes.Buffer

	// 		// Run main0
	// 		main0(tt.args, mockExit, &output)

	// 		// Check exit code if expected
	// 		if tt.wantExit != -1 {
	// 			assert.Equal(t, tt.wantExit, exitCode)
	// 		}

	// 		// Check output contains expected content if specified
	// 		if tt.wantOutput != "" {
	// 			assert.Contains(t, output.String(), tt.wantOutput)
	// 		}
	// 	})
	// }
}

// // broken out for testing
// func main0(args []string, exit func(int), output io.Writer) {
// 	// parse cli options
// 	options := options(args, exit)
// 	defer options.File.Close()

// 	// read csv
// 	csv := csv.NewReader(options.File)
// 	records, err := csv.ReadAll()
// 	if err != nil {
// 		// REMIND: make this red!
// 		fmt.Printf("tennis: could not read csv - %s", err.Error())
// 		exit(1)
// 	}

// 	// table
// 	table := tennis.NewTable(output)
// 	table.Color = tennis.StringToColor(options.Color)
// 	table.Theme = tennis.StringToTheme(options.Theme)
// 	table.RowNumbers = options.RowNumbers
// 	table.WriteAll(records)
// }
