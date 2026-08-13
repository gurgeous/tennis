// Ansi256 colors, see https://ansi.md.
#[allow(dead_code)] // Full palette; themes use a subset.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Ansi256 {
  Black,
  Navy,
  Darkblue,
  Dukeblue,
  Mediumblue,
  Blue,
  Darkgreen,
  Bluestone,
  Seablue,
  Endeavour,
  Royalblue,
  Blueribbon,
  Green,
  Seagreen,
  Darkcyan,
  Bubbles,
  Strongblue,
  Dodgerblue,
  Phosphor,
  Jade,
  Arcadia,
  Lightseagreen,
  Cerulean,
  Deepskyblue,
  Limegreen,
  Malachite,
  Underwater,
  Oceanic,
  Mediumturquoise,
  Neonblue,
  Lime,
  Cathode,
  Springgreen,
  Mediumspringgreen,
  Plunge,
  Aqua,
  Rosewood,
  Imperial,
  Indigo,
  Rebeccapurple,
  Spaceopera,
  Electricindigo,
  Darkolivegreen,
  Scorpion,
  Comet,
  Liberty,
  Slateblue,
  Genie,
  Olivedrab,
  Glade,
  Juniper,
  Steelblue,
  Cornflowerblue,
  Blueberry,
  Kermit,
  Mediumseagreen,
  Verdigris,
  Tradewind,
  Flyway,
  Bluejeans,
  Corrosive,
  Koopa,
  Snowpea,
  Mediumaquamarine,
  Viking,
  Athena,
  Lawngreen,
  Scream,
  Flora,
  Venice,
  Spindrift,
  Cyan,
  Darkred,
  Purple,
  Darkmagenta,
  Poison,
  Darkviolet,
  Blueviolet,
  Brown,
  Copper,
  Candy,
  Deluge,
  Gloomy,
  Mediumslateblue,
  Olive,
  Shadow,
  Mithril,
  Shadowblue,
  Ube,
  Periwinkle,
  Applegreen,
  Asparagus,
  Darkseagreen,
  Gulfstream,
  Polo,
  Malibu,
  Pistachio,
  Lettuce,
  Garden,
  Vista,
  Skyblue,
  Lightskyblue,
  Chartreuse,
  Stadium,
  Palegreen,
  Fungus,
  Aquamarine,
  Glitter,
  Firebrick,
  Darkpink,
  Flirt,
  Pirate,
  Darkorchid,
  Brightviolet,
  Sienna,
  Matrix,
  Tapestry,
  Pearlypurple,
  Mediumorchid,
  Hedonist,
  Darkgoldenrod,
  Bronze,
  Rosybrown,
  Bouquet,
  Blossom,
  Illicit,
  Mustard,
  Darkkhaki,
  Sage,
  Tinfoil,
  Lightsteelblue,
  Melrose,
  Kinglime,
  Conifer,
  Wasabi,
  Fizz,
  Lightblue,
  Droplet,
  Greenyellow,
  Inchworm,
  Mintgreen,
  Menthol,
  Aeroblue,
  Celeste,
  Crimson,
  Debianred,
  Mediumvioletred,
  Explosive,
  Deepmagenta,
  Phlox,
  Chocolate,
  Chestnut,
  Palevioletred,
  Superpink,
  Orchid,
  Heliotrope,
  Peru,
  Coppertan,
  Lightcoral,
  Cancan,
  Deepmauve,
  Lilac,
  Goldenrod,
  Equator,
  Tan,
  Clam,
  Thistle,
  Mauve,
  Corn,
  Energized,
  Deco,
  Greenmist,
  Tundra,
  Lavender,
  Limezest,
  Spritz,
  Honeysuckle,
  Reef,
  Frost,
  Lightcyan,
  Red,
  Raspberry,
  Deeppink,
  Purepink,
  Vicecity,
  Fuchsia,
  Blaze,
  Tomato,
  Strawberry,
  Hotpink,
  Rosepink,
  Flamingo,
  Darkorange,
  Coral,
  Salmon,
  Pinksalmon,
  Pout,
  Violet,
  Orange,
  Sandybrown,
  Lightsalmon,
  Lightpink,
  Cottoncandy,
  Shampoo,
  Gold,
  Lightgoldenrod,
  Jasmine,
  Peachpuff,
  Mistyrose,
  Bubblegum,
  Yellow,
  Canary,
  Dolly,
  Lemonchiffon,
  Lightyellow,
  White,
  Gray1,
  Gray2,
  Gray3,
  Gray4,
  Gray5,
  Gray6,
  Gray7,
  Gray8,
  Gray9,
  Gray10,
  Gray11,
  Gray12,
  Gray13,
  Gray14,
  Gray15,
  Gray16,
  Gray17,
  Gray18,
  Gray19,
  Gray20,
  Gray21,
  Gray22,
  Gray23,
  Gray24,
  Dimgray,
  Gray,
  Darkgray,
  Silver,
  Lightgray,
  Gainsboro,
}

impl Ansi256 {
  pub const fn index(self) -> u8 {
    match self {
      // red = 0x00
      Self::Black => 16,             // #000000
      Self::Navy => 17,              // #00005f
      Self::Darkblue => 18,          // #000087
      Self::Dukeblue => 19,          // #0000af
      Self::Mediumblue => 20,        // #0000d7
      Self::Blue => 21,              // #0000ff
      Self::Darkgreen => 22,         // #005f00
      Self::Bluestone => 23,         // #005f5f
      Self::Seablue => 24,           // #005f87
      Self::Endeavour => 25,         // #005faf
      Self::Royalblue => 26,         // #005fd7
      Self::Blueribbon => 27,        // #005fff
      Self::Green => 28,             // #008700
      Self::Seagreen => 29,          // #00875f
      Self::Darkcyan => 30,          // #008787
      Self::Bubbles => 31,           // #0087af
      Self::Strongblue => 32,        // #0087d7
      Self::Dodgerblue => 33,        // #0087ff
      Self::Phosphor => 34,          // #00af00
      Self::Jade => 35,              // #00af5f
      Self::Arcadia => 36,           // #00af87
      Self::Lightseagreen => 37,     // #00afaf
      Self::Cerulean => 38,          // #00afd7
      Self::Deepskyblue => 39,       // #00afff
      Self::Limegreen => 40,         // #00d700
      Self::Malachite => 41,         // #00d75f
      Self::Underwater => 42,        // #00d787
      Self::Oceanic => 43,           // #00d7af
      Self::Mediumturquoise => 44,   // #00d7d7
      Self::Neonblue => 45,          // #00d7ff
      Self::Lime => 46,              // #00ff00
      Self::Cathode => 47,           // #00ff5f
      Self::Springgreen => 48,       // #00ff87
      Self::Mediumspringgreen => 49, // #00ffaf
      Self::Plunge => 50,            // #00ffd7
      Self::Aqua => 51,              // #00ffff

      // red = 0x5f
      Self::Rosewood => 52,         // #5f0000
      Self::Imperial => 53,         // #5f005f
      Self::Indigo => 54,           // #5f0087
      Self::Rebeccapurple => 55,    // #5f00af
      Self::Spaceopera => 56,       // #5f00d7
      Self::Electricindigo => 57,   // #5f00ff
      Self::Darkolivegreen => 58,   // #5f5f00
      Self::Scorpion => 59,         // #5f5f5f
      Self::Comet => 60,            // #5f5f87
      Self::Liberty => 61,          // #5f5faf
      Self::Slateblue => 62,        // #5f5fd7
      Self::Genie => 63,            // #5f5fff
      Self::Olivedrab => 64,        // #5f8700
      Self::Glade => 65,            // #5f875f
      Self::Juniper => 66,          // #5f8787
      Self::Steelblue => 67,        // #5f87af
      Self::Cornflowerblue => 68,   // #5f87d7
      Self::Blueberry => 69,        // #5f87ff
      Self::Kermit => 70,           // #5faf00
      Self::Mediumseagreen => 71,   // #5faf5f
      Self::Verdigris => 72,        // #5faf87
      Self::Tradewind => 73,        // #5fafaf
      Self::Flyway => 74,           // #5fafd7
      Self::Bluejeans => 75,        // #5fafff
      Self::Corrosive => 76,        // #5fd700
      Self::Koopa => 77,            // #5fd75f
      Self::Snowpea => 78,          // #5fd787
      Self::Mediumaquamarine => 79, // #5fd7af
      Self::Viking => 80,           // #5fd7d7
      Self::Athena => 81,           // #5fd7ff
      Self::Lawngreen => 82,        // #5fff00
      Self::Scream => 83,           // #5fff5f
      Self::Flora => 84,            // #5fff87
      Self::Venice => 85,           // #5fffaf
      Self::Spindrift => 86,        // #5fffd7
      Self::Cyan => 87,             // #5fffff

      // red = 0x87
      Self::Darkred => 88,         // #870000
      Self::Purple => 89,          // #87005f
      Self::Darkmagenta => 90,     // #870087
      Self::Poison => 91,          // #8700af
      Self::Darkviolet => 92,      // #8700d7
      Self::Blueviolet => 93,      // #8700ff
      Self::Brown => 94,           // #875f00
      Self::Copper => 95,          // #875f5f
      Self::Candy => 96,           // #875f87
      Self::Deluge => 97,          // #875faf
      Self::Gloomy => 98,          // #875fd7
      Self::Mediumslateblue => 99, // #875fff
      Self::Olive => 100,          // #878700
      Self::Shadow => 101,         // #87875f
      Self::Mithril => 102,        // #878787
      Self::Shadowblue => 103,     // #8787af
      Self::Ube => 104,            // #8787d7
      Self::Periwinkle => 105,     // #8787ff
      Self::Applegreen => 106,     // #87af00
      Self::Asparagus => 107,      // #87af5f
      Self::Darkseagreen => 108,   // #87af87
      Self::Gulfstream => 109,     // #87afaf
      Self::Polo => 110,           // #87afd7
      Self::Malibu => 111,         // #87afff
      Self::Pistachio => 112,      // #87d700
      Self::Lettuce => 113,        // #87d75f
      Self::Garden => 114,         // #87d787
      Self::Vista => 115,          // #87d7af
      Self::Skyblue => 116,        // #87d7d7
      Self::Lightskyblue => 117,   // #87d7ff
      Self::Chartreuse => 118,     // #87ff00
      Self::Stadium => 119,        // #87ff5f
      Self::Palegreen => 120,      // #87ff87
      Self::Fungus => 121,         // #87ffaf
      Self::Aquamarine => 122,     // #87ffd7
      Self::Glitter => 123,        // #87ffff

      // red = 0xaf
      Self::Firebrick => 124,      // #af0000
      Self::Darkpink => 125,       // #af005f
      Self::Flirt => 126,          // #af0087
      Self::Pirate => 127,         // #af00af
      Self::Darkorchid => 128,     // #af00d7
      Self::Brightviolet => 129,   // #af00ff
      Self::Sienna => 130,         // #af5f00
      Self::Matrix => 131,         // #af5f5f
      Self::Tapestry => 132,       // #af5f87
      Self::Pearlypurple => 133,   // #af5faf
      Self::Mediumorchid => 134,   // #af5fd7
      Self::Hedonist => 135,       // #af5fff
      Self::Darkgoldenrod => 136,  // #af8700
      Self::Bronze => 137,         // #af875f
      Self::Rosybrown => 138,      // #af8787
      Self::Bouquet => 139,        // #af87af
      Self::Blossom => 140,        // #af87d7
      Self::Illicit => 141,        // #af87ff
      Self::Mustard => 142,        // #afaf00
      Self::Darkkhaki => 143,      // #afaf5f
      Self::Sage => 144,           // #afaf87
      Self::Tinfoil => 145,        // #afafaf
      Self::Lightsteelblue => 146, // #afafd7
      Self::Melrose => 147,        // #afafff
      Self::Kinglime => 148,       // #afd700
      Self::Conifer => 149,        // #afd75f
      Self::Wasabi => 150,         // #afd787
      Self::Fizz => 151,           // #afd7af
      Self::Lightblue => 152,      // #afd7d7
      Self::Droplet => 153,        // #afd7ff
      Self::Greenyellow => 154,    // #afff00
      Self::Inchworm => 155,       // #afff5f
      Self::Mintgreen => 156,      // #afff87
      Self::Menthol => 157,        // #afffaf
      Self::Aeroblue => 158,       // #afffd7
      Self::Celeste => 159,        // #afffff

      // red = 0xd7
      Self::Crimson => 160,         // #d70000
      Self::Debianred => 161,       // #d7005f
      Self::Mediumvioletred => 162, // #d70087
      Self::Explosive => 163,       // #d700af
      Self::Deepmagenta => 164,     // #d700d7
      Self::Phlox => 165,           // #d700ff
      Self::Chocolate => 166,       // #d75f00
      Self::Chestnut => 167,        // #d75f5f
      Self::Palevioletred => 168,   // #d75f87
      Self::Superpink => 169,       // #d75faf
      Self::Orchid => 170,          // #d75fd7
      Self::Heliotrope => 171,      // #d75fff
      Self::Peru => 172,            // #d78700
      Self::Coppertan => 173,       // #d7875f
      Self::Lightcoral => 174,      // #d78787
      Self::Cancan => 175,          // #d787af
      Self::Deepmauve => 176,       // #d787d7
      Self::Lilac => 177,           // #d787ff
      Self::Goldenrod => 178,       // #d7af00
      Self::Equator => 179,         // #d7af5f
      Self::Tan => 180,             // #d7af87
      Self::Clam => 181,            // #d7afaf
      Self::Thistle => 182,         // #d7afd7
      Self::Mauve => 183,           // #d7afff
      Self::Corn => 184,            // #d7d700
      Self::Energized => 185,       // #d7d75f
      Self::Deco => 186,            // #d7d787
      Self::Greenmist => 187,       // #d7d7af
      Self::Tundra => 188,          // #d7d7d7
      Self::Lavender => 189,        // #d7d7ff
      Self::Limezest => 190,        // #d7ff00
      Self::Spritz => 191,          // #d7ff5f
      Self::Honeysuckle => 192,     // #d7ff87
      Self::Reef => 193,            // #d7ffaf
      Self::Frost => 194,           // #d7ffd7
      Self::Lightcyan => 195,       // #d7ffff

      // red = 0xff
      Self::Red => 196,            // #ff0000
      Self::Raspberry => 197,      // #ff005f
      Self::Deeppink => 198,       // #ff0087
      Self::Purepink => 199,       // #ff00af
      Self::Vicecity => 200,       // #ff00d7
      Self::Fuchsia => 201,        // #ff00ff
      Self::Blaze => 202,          // #ff5f00
      Self::Tomato => 203,         // #ff5f5f
      Self::Strawberry => 204,     // #ff5f87
      Self::Hotpink => 205,        // #ff5faf
      Self::Rosepink => 206,       // #ff5fd7
      Self::Flamingo => 207,       // #ff5fff
      Self::Darkorange => 208,     // #ff8700
      Self::Coral => 209,          // #ff875f
      Self::Salmon => 210,         // #ff8787
      Self::Pinksalmon => 211,     // #ff87af
      Self::Pout => 212,           // #ff87d7
      Self::Violet => 213,         // #ff87ff
      Self::Orange => 214,         // #ffaf00
      Self::Sandybrown => 215,     // #ffaf5f
      Self::Lightsalmon => 216,    // #ffaf87
      Self::Lightpink => 217,      // #ffafaf
      Self::Cottoncandy => 218,    // #ffafd7
      Self::Shampoo => 219,        // #ffafff
      Self::Gold => 220,           // #ffd700
      Self::Lightgoldenrod => 221, // #ffd75f
      Self::Jasmine => 222,        // #ffd787
      Self::Peachpuff => 223,      // #ffd7af
      Self::Mistyrose => 224,      // #ffd7d7
      Self::Bubblegum => 225,      // #ffd7ff
      Self::Yellow => 226,         // #ffff00
      Self::Canary => 227,         // #ffff5f
      Self::Dolly => 228,          // #ffff87
      Self::Lemonchiffon => 229,   // #ffffaf
      Self::Lightyellow => 230,    // #ffffd7
      Self::White => 231,          // #ffffff

      // grayscale
      Self::Gray1 => 232,  // #080808
      Self::Gray2 => 233,  // #121212
      Self::Gray3 => 234,  // #1c1c1c
      Self::Gray4 => 235,  // #262626
      Self::Gray5 => 236,  // #303030
      Self::Gray6 => 237,  // #3a3a3a
      Self::Gray7 => 238,  // #444444
      Self::Gray8 => 239,  // #4e4e4e
      Self::Gray9 => 240,  // #585858
      Self::Gray10 => 241, // #626262
      Self::Gray11 => 242, // #6c6c6c
      Self::Gray12 => 243, // #767676
      Self::Gray13 => 244, // #808080
      Self::Gray14 => 245, // #8a8a8a
      Self::Gray15 => 246, // #949494
      Self::Gray16 => 247, // #9e9e9e
      Self::Gray17 => 248, // #a8a8a8
      Self::Gray18 => 249, // #b2b2b2
      Self::Gray19 => 250, // #bcbcbc
      Self::Gray20 => 251, // #c6c6c6
      Self::Gray21 => 252, // #d0d0d0
      Self::Gray22 => 253, // #dadada
      Self::Gray23 => 254, // #e4e4e4
      Self::Gray24 => 255, // #eeeeee

      // gray aliases from css
      Self::Dimgray => 242,   // #6c6c6c
      Self::Gray => 244,      // #808080
      Self::Darkgray => 248,  // #a8a8a8
      Self::Silver => 250,    // #bcbcbc
      Self::Lightgray => 252, // #d0d0d0
      Self::Gainsboro => 253, // #dadada
    }
  }
}
