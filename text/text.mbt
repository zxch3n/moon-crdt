pub struct Text {
  text : String
  char_len : Int
}

pub fn rle_len(self : Text) -> Int {
  self.char_len
}

impl @rle.Rle for Text with can_merge(text1 : Text, text2 : Text) -> Bool {
  text1.char_len + text2.char_len <= 8
}

impl @rle.Rle for Text with merge(text1 : Text, text2 : Text) -> Text {
  Text::{
    text: text1.text + text2.text,
    char_len: text1.char_len + text2.char_len,
  }
}

pub fn slice(self : Text, start : Int, end : Int) -> Text {
  Text::{ text: self.text.substring(~start, ~end), char_len: end - start }
}

pub struct TextRope {
  tree : @btree.BTree[Text]
}

pub fn new(~max_child_num : Int = 12) -> TextRope {
  TextRope::{ tree: @btree.new(~max_child_num) }
}

pub fn insert(self : TextRope, index : Int, text : String) -> Unit {
  self.tree.insert(index, Text::{ text, char_len: text.length() })
}

pub fn to_string(self : TextRope) -> String {
  let mut result = ""
  for text in self.tree.iter() {
    result += text.text
  }
  result
}

test "basic rope insertions" {
  let rope = new()
  rope.insert(0, "Hello, ")
  rope.insert(7, "world!")
  assert_eq!(rope.to_string(), "Hello, world!")
  rope.insert(7, "beautiful ")
  assert_eq!(rope.to_string(), "Hello, beautiful world!")
  rope.insert(0, "Start of the rope: ")
  assert_eq!(rope.to_string(), "Start of the rope: Hello, beautiful world!")
}

fn repeat(s : String, n : Int) -> String {
  let mut result = ""
  for i = 0; i < n; i = i + 1 {
    result += s
  }
  result
}

fn to_string(self : Text) -> String {
  self.text
}

fn output(self : Text, logger : Logger) -> Unit {
  logger.write_string(self.text)
}

pub fn length(self : TextRope) -> Int {
  self.tree.len()
}

test "complex rope insertions" {
  let rope = new(max_child_num=6)
  // Insert a long string that will be split multiple times
  let long_string = repeat("abcdefghijklmnopqrstuvwxyz", 10) // 260 characters
  rope.insert(0, long_string)
  assert_eq!(rope.to_string(), long_string)
  inspect!(
    rope.tree,
    content="Leaf(len=260): [abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz]",
  )
  for i = 0; i < 5; i = i + 1 {
    rope.insert(10 * i, "START")
  }
  inspect!(
    rope.tree,
    content=
      #|Node(len=285):
      #|  Leaf(len=15): [START, abcde, START]
      #|  Leaf(len=15): [fghij, START, klmno]
      #|  Leaf(len=255): [START, pqrst, START, uvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz]
  )
  for i = 0; i < 10; i = i + 1 {
    rope.insert(10 * i % rope.length(), "START")
  }
  inspect!(
    rope.tree,
    content=
      #|Node(len=335):
      #|  Node(len=45):
      #|    Leaf(len=15): [START, START, START]
      #|    Leaf(len=15): [abcde, START, START]
      #|    Leaf(len=15): [START, fghij, START]
      #|  Node(len=290):
      #|    Leaf(len=15): [START, START, klmno]
      #|    Leaf(len=15): [START, START, START]
      #|    Leaf(len=260): [pqrst, START, START, START, uvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz]
    ,
  )
  for i = 14; i < 15; i = i + 1 {
    rope.insert(10 * i % rope.length(), "START")
  }
  inspect!(
    rope.tree,
    content=
      #|Node(len=340):
      #|  Node(len=45):
      #|    Leaf(len=15): [START, START, START]
      #|    Leaf(len=15): [abcde, START, START]
      #|    Leaf(len=15): [START, fghij, START]
      #|  Node(len=295):
      #|    Leaf(len=15): [START, START, klmno]
      #|    Leaf(len=15): [START, START, START]
      #|    Leaf(len=15): [pqrst, START, START]
      #|    Leaf(len=250): [START, uvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklm, START, nopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz]
    ,
  )
  rope.tree.check_integrity!()
  // Insert shorter strings at various positions to force splits
  for i = 0; i < 5 * 8; i = i + 1 {
    let insert_pos = i * 8
    rope.insert(insert_pos, "SPLIT")
  }

  // Insert at the beginning and end to test edge cases
  rope.insert(0, "START")
  rope.tree.check_integrity!()
  inspect!(
    rope.tree,
    content=
      #|Node(len=545):
      #|  Node(len=60):
      #|    Leaf(len=20): [START, SPLIT, STASPLIT, RT]
      #|    Leaf(len=25): [SSPLIT, TARSPLIT, T, STSPLIT, ART]
      #|    Leaf(len=15): [SPLIT, abcSPLIT, de]
      #|  Node(len=65):
      #|    Leaf(len=25): [SSPLIT, TARSPLIT, T, STSPLIT, ART]
      #|    Leaf(len=15): [SPLIT, STASPLIT, RT]
      #|    Leaf(len=25): [fSPLIT, ghiSPLIT, j, STSPLIT, ART]
      #|  Node(len=55):
      #|    Leaf(len=15): [SPLIT, STASPLIT, RT]
      #|    Leaf(len=25): [SSPLIT, TARSPLIT, T, klSPLIT, mno]
      #|    Leaf(len=15): [SPLIT, STASPLIT, RT]
      #|  Node(len=65):
      #|    Leaf(len=25): [SSPLIT, TARSPLIT, T, STSPLIT, ART]
      #|    Leaf(len=15): [SPLIT, pqrSPLIT, st]
      #|    Leaf(len=25): [SSPLIT, TARSPLIT, T, STSPLIT, ART]
      #|  Node(len=300):
      #|    Leaf(len=15): [SPLIT, STASPLIT, RT]
      #|    Leaf(len=22): [uSPLIT, vwxSPLIT, yzaSPLIT]
      #|    Leaf(len=24): [bcdSPLIT, efgSPLIT, hijSPLIT]
      #|    Leaf(len=239): [klmSPLIT, nopSPLIT, qrstuvwxyzabcdefghijklm, START, nopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz]
    ,
  )
  rope.tree.check_integrity!()
  assert_eq!(rope.to_string().length(), rope.length())
  inspect!(rope.tree.query(rope.length() - 1), content="Some(4, 3, 4,  | 194)")
  inspect!(rope.tree.query(rope.length()), content="Some(4, 3, 5,  | 0)")
  rope.tree.check_integrity!()
  rope.insert(rope.to_string().length(), "END")
  inspect!(
    rope.tree,
    content=
      #|Node(len=548):
      #|  Node(len=60):
      #|    Leaf(len=20): [START, SPLIT, STASPLIT, RT]
      #|    Leaf(len=25): [SSPLIT, TARSPLIT, T, STSPLIT, ART]
      #|    Leaf(len=15): [SPLIT, abcSPLIT, de]
      #|  Node(len=65):
      #|    Leaf(len=25): [SSPLIT, TARSPLIT, T, STSPLIT, ART]
      #|    Leaf(len=15): [SPLIT, STASPLIT, RT]
      #|    Leaf(len=25): [fSPLIT, ghiSPLIT, j, STSPLIT, ART]
      #|  Node(len=55):
      #|    Leaf(len=15): [SPLIT, STASPLIT, RT]
      #|    Leaf(len=25): [SSPLIT, TARSPLIT, T, klSPLIT, mno]
      #|    Leaf(len=15): [SPLIT, STASPLIT, RT]
      #|  Node(len=65):
      #|    Leaf(len=25): [SSPLIT, TARSPLIT, T, STSPLIT, ART]
      #|    Leaf(len=15): [SPLIT, pqrSPLIT, st]
      #|    Leaf(len=25): [SSPLIT, TARSPLIT, T, STSPLIT, ART]
      #|  Node(len=303):
      #|    Leaf(len=15): [SPLIT, STASPLIT, RT]
      #|    Leaf(len=22): [uSPLIT, vwxSPLIT, yzaSPLIT]
      #|    Leaf(len=24): [bcdSPLIT, efgSPLIT, hijSPLIT]
      #|    Leaf(len=39): [klmSPLIT, nopSPLIT, qrstuvwxyzabcdefghijklm]
      #|    Leaf(len=203): [START, nopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz, END]
    ,
  )

  // Verify the insertions
  assert_eq!(rope.to_string().substring(start=0, end=5), "START")
  assert_eq!(rope.to_string().substring(start=rope.length() - 3), "END")

  // Insert a medium-sized string in the middle
  let mid_pos = rope.to_string().length() / 2
  let mid_string = repeat("MIDDLE", 20) // 120 characters
  rope.insert(mid_pos, mid_string)

  // Verify the middle insertion
  assert_eq!(
    rope.to_string().substring(start=mid_pos, end=mid_pos + mid_string.length()),
    mid_string,
  )

  // Final length check
  assert_eq!(rope.to_string().length(), rope.length())
}
