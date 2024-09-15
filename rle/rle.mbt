pub trait Rle {
  rle_len(Self) -> Int
  can_merge(Self, Self) -> Bool
  merge(Self, Self) -> Self
  slice(Self, Int, Int) -> Self
}

pub fn split[V : Rle](v : V, index : Int) -> (V, V) {
  let len = v.rle_len()
  let left = v.slice(0, index)
  let right = v.slice(index, len)
  (left, right)
}
