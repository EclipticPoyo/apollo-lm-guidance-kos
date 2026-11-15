// dsky_store.ks -- the erasable store: named cells of 15-bit words, the way the DSKY's loaders (the keyed loads V21 to V25
// and the update program P27, V71/V72) see the computer's erasable memory. Vehicle-independent: the vehicle hands in its
// table of cells (see lm/lm_cells.ks for the LM's), and the core never names a cell.
//
// A cells table is a LEXICON: name -> LEXICON("BANK", n, "OFFSET", n, "WORDS", n, "SCALE", n, "LABEL", text). OFFSET is the
// address inside the bank as a decimal number (octal 1400 to 1777 is 768 to 1023). The store is
// LEXICON("CELLS", the table, "RAW", LEXICON): RAW maps a cell name to a LIST of its words (integers 0 to 32767, a negative
// number in one's complement), with -1 for a word not written yet; a cell has an entry once any of its words was written.
// Words inside a cell are numbered from 1.
//
// Double-precision numbers (dp_encode, dp_decode) are two words: 28 bits of magnitude, the same sign in both, as the AGC
// kept them. Words are 15 bits, bit 15 is the sign: 0 to 16383 is positive, 16384 to 32767 is negative (one's complement).

// store_new: an empty store for a table of cells.
FUNCTION store_new {
  PARAMETER cells.
  RETURN LEXICON("CELLS", cells, "RAW", LEXICON()).
}

// store_ecadr: the ECADR (bank * 256 + address inside the bank, counted from 768) of a cell's first word. The uplink
// (V71, V72) names words by ECADR; E4,1422 octal is 2022 octal (UPDATE_PROGRAM.agc, UPEND71).
FUNCTION store_ecadr {
  PARAMETER cells, name.
  RETURN cells[name]["BANK"] * 256 + cells[name]["OFFSET"] - 768.
}

// store_locate: which cell holds the word at this ECADR. LEXICON("NAME", cell name or "", "INDEX", word number from 1 or 0).
FUNCTION store_locate {
  PARAMETER vault, ecadr_value.
  LOCAL cells IS vault["CELLS"].
  FOR name IN cells:KEYS {
    LOCAL first IS store_ecadr(cells, name).
    IF ecadr_value >= first AND ecadr_value < first + cells[name]["WORDS"] {
      RETURN LEXICON("NAME", name, "INDEX", ecadr_value - first + 1).
    }
  }
  RETURN LEXICON("NAME", "", "INDEX", 0).
}

// store_put: write one word (index from 1) into a cell. FALSE when the cell or the index does not exist or the word is not
// a 15-bit number; nothing changes then.
FUNCTION store_put {
  PARAMETER vault, name, index, word.
  IF NOT vault["CELLS"]:HASKEY(name) { RETURN FALSE. }
  LOCAL count IS vault["CELLS"][name]["WORDS"].
  IF index < 1 OR index > count { RETURN FALSE. }
  IF word < 0 OR word > 32767 { RETURN FALSE. }
  IF NOT vault["RAW"]:HASKEY(name) {
    LOCAL blank IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= count STEP { SET i TO i + 1. } DO { blank:ADD(-1). }
    SET vault["RAW"][name] TO blank.
  }
  SET vault["RAW"][name][index - 1] TO word.
  RETURN TRUE.
}

// store_put_all: write every word of a cell (a LIST with exactly the cell's number of words). FALSE, nothing written, if
// the cell is unknown or the count or any word is wrong.
FUNCTION store_put_all {
  PARAMETER vault, name, words.
  IF NOT vault["CELLS"]:HASKEY(name) { RETURN FALSE. }
  IF words:LENGTH <> vault["CELLS"][name]["WORDS"] { RETURN FALSE. }
  FOR word IN words { IF word < 0 OR word > 32767 { RETURN FALSE. } }
  FROM { LOCAL i IS 0. } UNTIL i >= words:LENGTH STEP { SET i TO i + 1. } DO { store_put(vault, name, i + 1, words[i]). }
  RETURN TRUE.
}

// store_loaded: TRUE when every word of the cell has been written.
FUNCTION store_loaded {
  PARAMETER vault, name.
  IF NOT vault["RAW"]:HASKEY(name) { RETURN FALSE. }
  FOR word IN vault["RAW"][name] { IF word < 0 { RETURN FALSE. } }
  RETURN TRUE.
}

// store_words: a copy of the cell's words (-1 for one not written), or an empty LIST for a cell never written.
FUNCTION store_words {
  PARAMETER vault, name.
  LOCAL out IS LIST().
  IF vault["RAW"]:HASKEY(name) { FOR word IN vault["RAW"][name] { out:ADD(word). } }
  RETURN out.
}

// store_clear: forget a cell's words.
FUNCTION store_clear {
  PARAMETER vault, name.
  IF vault["RAW"]:HASKEY(name) { vault["RAW"]:REMOVE(name). }
}

// store_save: write the store to a text file so it outlives the DSKY program (the real erasable memory stays while the computer is
// on; here "on" is the game session, and the window's close cross ends the DSKY script). Line 1 is a tag the vehicle chooses (the cell table in use);
// then one line per written cell: its name and its words. Nothing is written for an empty store (and an old file is removed).
FUNCTION store_save {
  PARAMETER vault, path_str, tag.
  IF EXISTS(path_str) { DELETEPATH(path_str). }
  IF vault["RAW"]:LENGTH = 0 { RETURN. }
  LOG tag TO path_str.
  FOR name IN vault["RAW"]:KEYS {
    LOCAL line IS name.
    FOR word IN vault["RAW"][name] { SET line TO line + " " + word. }
    LOG line TO path_str.
  }
}

// store_restore: read a file written by store_save back into the store. Does nothing when the file is missing or its tag differs.
// A line for an unknown cell, or with the wrong number of words or a bad word, is skipped. Returns the number of cells restored.
FUNCTION store_restore {
  PARAMETER vault, path_str, tag.
  IF NOT EXISTS(path_str) { RETURN 0. }
  LOCAL lines IS OPEN(path_str):READALL:STRING:SPLIT(CHAR(10)).
  IF lines:LENGTH = 0 OR lines[0]:TRIM <> tag { RETURN 0. }
  LOCAL restored IS 0.
  FROM { LOCAL i IS 1. } UNTIL i >= lines:LENGTH STEP { SET i TO i + 1. } DO {
    LOCAL parts IS lines[i]:TRIM:SPLIT(" ").
    IF parts:LENGTH > 1 AND vault["CELLS"]:HASKEY(parts[0]) {
      IF parts:LENGTH - 1 = vault["CELLS"][parts[0]]["WORDS"] {
        LOCAL words IS LIST().
        LOCAL good IS TRUE.
        FROM { LOCAL k IS 1. } UNTIL k >= parts:LENGTH STEP { SET k TO k + 1. } DO {
          LOCAL value IS parts[k]:TONUMBER(-2).
          IF value < -1 OR value > 32767 { SET good TO FALSE. }
          words:ADD(value).
        }
        IF good {
          SET vault["RAW"][parts[0]] TO words.
          SET restored TO restored + 1.
        }
      }
    }
  }
  RETURN restored.
}

// octal_text: n in octal, left-padded with zeros to at least width digits (octal_text(8, 4) is "0010").
FUNCTION octal_text {
  PARAMETER n, width.
  LOCAL text IS "".
  LOCAL rest IS FLOOR(n).
  IF rest = 0 { SET text TO "0". }
  UNTIL rest = 0 {
    SET text TO "" + MOD(rest, 8) + text.
    SET rest TO FLOOR(rest / 8).
  }
  UNTIL text:LENGTH >= width { SET text TO "0" + text. }
  RETURN text.
}

// octal_parse: the number for a text of octal digits, or -1 for an empty text or any character that is not 0 to 7.
FUNCTION octal_parse {
  PARAMETER text.
  IF text:LENGTH = 0 { RETURN -1. }
  LOCAL total IS 0.
  FROM { LOCAL i IS 0. } UNTIL i >= text:LENGTH STEP { SET i TO i + 1. } DO {
    LOCAL digit IS "01234567":FIND(text:SUBSTRING(i, 1)).
    IF digit < 0 { RETURN -1. }
    SET total TO total * 8 + digit.
  }
  RETURN total.
}

// dp_encode: the two words (a LIST: high, low) for a value whose full scale is 2^scale_exp (the AGC's "B-n" scaling: B-27
// metres is scale_exp 27). 28 bits of magnitude, rounded; a value too big is clamped; a negative value is the one's complement
// of both words.
FUNCTION dp_encode {
  PARAMETER value, scale_exp.
  LOCAL fraction IS ABS(value) / 2 ^ scale_exp.
  LOCAL magnitude IS MIN(FLOOR(fraction * 268435456 + 0.5), 268435455).
  LOCAL high_word IS FLOOR(magnitude / 16384).
  LOCAL low_word IS magnitude - high_word * 16384.
  IF value < 0 AND magnitude > 0 {
    SET high_word TO 32767 - high_word.
    SET low_word TO 32767 - low_word.
  }
  RETURN LIST(high_word, low_word).
}

// dp_signed: a 15-bit word as a signed number (one's complement).
FUNCTION dp_signed {
  PARAMETER word.
  IF word >= 16384 { RETURN -(32767 - word). }
  RETURN word.
}

// dp_decode: the value of a double-precision word pair at full scale 2^scale_exp. Words that disagree in sign add as signed
// numbers, as the AGC's double-precision add does.
FUNCTION dp_decode {
  PARAMETER words, scale_exp.
  RETURN (dp_signed(words[0]) * 16384 + dp_signed(words[1])) / 268435456 * 2 ^ scale_exp.
}
