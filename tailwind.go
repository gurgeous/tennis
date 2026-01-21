package tennis

//
// tailwind colors in golang
//

var Tailwind = &tailwind{
	Rose: palette{
		c50:  "#fff1f2",
		c100: "#ffe4e6",
		c200: "#fecdd3",
		c300: "#fda4af",
		c400: "#fb7185",
		c500: "#f43f5e",
		c600: "#e11d48",
		c700: "#be123c",
		c800: "#9f1239",
		c900: "#881337",
		c950: "#4c0519",
	},

	Slate: palette{
		c50:  "#f8fafc",
		c100: "#f1f5f9",
		c200: "#e2e8f0",
		c300: "#cbd5e1",
		c400: "#94a3b8",
		c500: "#64748b",
		c600: "#475569",
		c700: "#334155",
		c800: "#1e293b",
		c900: "#0f172a",
		c950: "#020617",
	},

	Gray: palette{
		c50:  "#f9fafb",
		c100: "#f3f4f6",
		c200: "#e5e7eb",
		c300: "#d1d5db",
		c400: "#9ca3af",
		c500: "#6b7280",
		c600: "#4b5563",
		c700: "#374151",
		c800: "#1f2937",
		c900: "#111827",
		c950: "#030712",
	},

	Zinc: palette{
		c50:  "#fafafa",
		c100: "#f4f4f5",
		c200: "#e4e4e7",
		c300: "#d4d4d8",
		c400: "#a1a1aa",
		c500: "#71717a",
		c600: "#52525b",
		c700: "#3f3f46",
		c800: "#27272a",
		c900: "#18181b",
		c950: "#09090b",
	},

	Neutral: palette{
		c50:  "#fafafa",
		c100: "#f5f5f5",
		c200: "#e5e5e5",
		c300: "#d4d4d4",
		c400: "#a3a3a3",
		c500: "#737373",
		c600: "#525252",
		c700: "#404040",
		c800: "#262626",
		c900: "#171717",
		c950: "#0a0a0a",
	},
	Stone: palette{
		c50:  "#fafaf9",
		c100: "#f5f5f4",
		c200: "#e7e5e4",
		c300: "#d6d3d1",
		c400: "#a8a29e",
		c500: "#78716c",
		c600: "#57534e",
		c700: "#44403c",
		c800: "#292524",
		c900: "#1c1917",
		c950: "#0c0a09",
	},
	Red: palette{
		c50:  "#fef2f2",
		c100: "#fee2e2",
		c200: "#fecaca",
		c300: "#fca5a5",
		c400: "#f87171",
		c500: "#ef4444",
		c600: "#dc2626",
		c700: "#b91c1c",
		c800: "#991b1b",
		c900: "#7f1d1d",
		c950: "#450a0a",
	},
	Orange: palette{
		c50:  "#fff7ed",
		c100: "#ffedd5",
		c200: "#fed7aa",
		c300: "#fdba74",
		c400: "#fb923c",
		c500: "#f97316",
		c600: "#ea580c",
		c700: "#c2410c",
		c800: "#9a3412",
		c900: "#7c2d12",
		c950: "#431407",
	},
	Amber: palette{
		c50:  "#fffbeb",
		c100: "#fef3c7",
		c200: "#fde68a",
		c300: "#fcd34d",
		c400: "#fbbf24",
		c500: "#f59e0b",
		c600: "#d97706",
		c700: "#b45309",
		c800: "#92400e",
		c900: "#78350f",
		c950: "#451a03",
	},
	Yellow: palette{
		c50:  "#fefce8",
		c100: "#fef9c3",
		c200: "#fef08a",
		c300: "#fde047",
		c400: "#facc15",
		c500: "#eab308",
		c600: "#ca8a04",
		c700: "#a16207",
		c800: "#854d0e",
		c900: "#713f12",
		c950: "#422006",
	},
	Lime: palette{
		c50:  "#f7fee7",
		c100: "#ecfccb",
		c200: "#d9f99d",
		c300: "#bef264",
		c400: "#a3e635",
		c500: "#84cc16",
		c600: "#65a30d",
		c700: "#4d7c0f",
		c800: "#3f6212",
		c900: "#365314",
		c950: "#1a2e05",
	},
	Green: palette{
		c50:  "#f0fdf4",
		c100: "#dcfce7",
		c200: "#bbf7d0",
		c300: "#86efac",
		c400: "#4ade80",
		c500: "#22c55e",
		c600: "#16a34a",
		c700: "#15803d",
		c800: "#166534",
		c900: "#14532d",
		c950: "#052e16",
	},
	Emerald: palette{
		c50:  "#ecfdf5",
		c100: "#d1fae5",
		c200: "#a7f3d0",
		c300: "#6ee7b7",
		c400: "#34d399",
		c500: "#10b981",
		c600: "#059669",
		c700: "#047857",
		c800: "#065f46",
		c900: "#064e3b",
		c950: "#022c22",
	},
	Teal: palette{
		c50:  "#f0fdfa",
		c100: "#ccfbf1",
		c200: "#99f6e4",
		c300: "#5eead4",
		c400: "#2dd4bf",
		c500: "#14b8a6",
		c600: "#0d9488",
		c700: "#0f766e",
		c800: "#115e59",
		c900: "#134e4a",
		c950: "#042f2e",
	},
	Cyan: palette{
		c50:  "#ecfeff",
		c100: "#cffafe",
		c200: "#a5f3fc",
		c300: "#67e8f9",
		c400: "#22d3ee",
		c500: "#06b6d4",
		c600: "#0891b2",
		c700: "#0e7490",
		c800: "#155e75",
		c900: "#164e63",
		c950: "#083344",
	},
	Sky: palette{
		c50:  "#f0f9ff",
		c100: "#e0f2fe",
		c200: "#bae6fd",
		c300: "#7dd3fc",
		c400: "#38bdf8",
		c500: "#0ea5e9",
		c600: "#0284c7",
		c700: "#0369a1",
		c800: "#075985",
		c900: "#0c4a6e",
		c950: "#082f49",
	},
	Blue: palette{
		c50:  "#eff6ff",
		c100: "#dbeafe",
		c200: "#bfdbfe",
		c300: "#93c5fd",
		c400: "#60a5fa",
		c500: "#3b82f6",
		c600: "#2563eb",
		c700: "#1d4ed8",
		c800: "#1e40af",
		c900: "#1e3a8a",
		c950: "#172554",
	},
	Indigo: palette{
		c50:  "#eef2ff",
		c100: "#e0e7ff",
		c200: "#c7d2fe",
		c300: "#a5b4fc",
		c400: "#818cf8",
		c500: "#6366f1",
		c600: "#4f46e5",
		c700: "#4338ca",
		c800: "#3730a3",
		c900: "#312e81",
		c950: "#1e1b4b",
	},
	Violet: palette{
		c50:  "#f5f3ff",
		c100: "#ede9fe",
		c200: "#ddd6fe",
		c300: "#c4b5fd",
		c400: "#a78bfa",
		c500: "#8b5cf6",
		c600: "#7c3aed",
		c700: "#6d28d9",
		c800: "#5b21b6",
		c900: "#4c1d95",
		c950: "#2e1065",
	},
	Purple: palette{
		c50:  "#faf5ff",
		c100: "#f3e8ff",
		c200: "#e9d5ff",
		c300: "#d8b4fe",
		c400: "#c084fc",
		c500: "#a855f7",
		c600: "#9333ea",
		c700: "#7e22ce",
		c800: "#6b21a8",
		c900: "#581c87",
		c950: "#3b0764",
	},
	Fuchsia: palette{
		c50:  "#fdf4ff",
		c100: "#fae8ff",
		c200: "#f5d0fe",
		c300: "#f0abfc",
		c400: "#e879f9",
		c500: "#d946ef",
		c600: "#c026d3",
		c700: "#a21caf",
		c800: "#86198f",
		c900: "#701a75",
		c950: "#4a044e",
	},
	Pink: palette{
		c50:  "#fdf2f8",
		c100: "#fce7f3",
		c200: "#fbcfe8",
		c300: "#f9a8d4",
		c400: "#f472b6",
		c500: "#ec4899",
		c600: "#db2777",
		c700: "#be185d",
		c800: "#9d174d",
		c900: "#831843",
		c950: "#500724",
	},
}

type tailwind struct {
	Rose    palette
	Slate   palette
	Gray    palette
	Zinc    palette
	Neutral palette
	Stone   palette
	Red     palette
	Orange  palette
	Amber   palette
	Yellow  palette
	Lime    palette
	Green   palette
	Emerald palette
	Teal    palette
	Cyan    palette
	Sky     palette
	Blue    palette
	Indigo  palette
	Violet  palette
	Purple  palette
	Fuchsia palette
	Pink    palette
}

type palette struct {
	c50  string
	c100 string
	c200 string
	c300 string
	c400 string
	c500 string
	c600 string
	c700 string
	c800 string
	c900 string
	c950 string
}
