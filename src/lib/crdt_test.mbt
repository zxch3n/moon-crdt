test "basic insert delete" {
  let crdt = @lib.Crdt::new(0)
  crdt.insert_str!(0, "hello")
  inspect!(crdt.to_string(), content="hello")
  crdt.delete!(1)
  inspect!(crdt.to_string(), content="hllo")
  crdt.delete!(0, len=2)
  inspect!(crdt.to_string(), content="lo")
  crdt.insert_str!(1, " hi_")
  inspect!(crdt.to_string(), content="l hi_o")
  crdt.delete!(1, len=3)
  inspect!(crdt.to_string(), content="l_o")
  assert_eq!(crdt.length(), 3)
}

test "id ord" {
  let id0 = @lib.Id::{ lamport: 2, peer: 0 }
  let id1 = @lib.Id::{ lamport: 0, peer: 2 }
  assert_true!(id0 > id1)
}

test "merge" {
  let a = @lib.Crdt::new(0)
  let b = @lib.Crdt::new(1)
  a.insert_str!(0, "12345")
  a.merge!(b)
  assert_eq!(a.to_string(), b.to_string())
  a.delete!(0, len=3)
  a.merge!(b)
  assert_eq!(a.to_string(), b.to_string())
  inspect!(a.to_string(), content="45")
  a.insert_str!(0, "Hello")
  inspect!(a.to_string(), content="Hello45")
  b.insert_str!(0, "World")
  inspect!(b.to_string(), content="World45")
  a.merge!(b)
  inspect!(a.to_string(), content="WorldHello45")
  inspect!(b.to_string(), content="WorldHello45")
}

test "merge" {
  let a = @lib.Crdt::new(0)
  let b = @lib.Crdt::new(1)
  let c = @lib.Crdt::new(2)
  a.insert_str!(0, "123")
  b.insert_str!(0, "abc")
  c.insert_str!(0, "xy")
  a.merge!(b)
  b.merge!(c)
  c.merge!(a)
  inspect!(a.to_string(), content="xyabc123")
  inspect!(b.to_string(), content="xyabc123")
  inspect!(c.to_string(), content="xyabc123")
  c.delete!(0, len=3)
  b.delete!(0, len=5)
  c.apply!(b.export_from(Map::new()))
  inspect!(c.to_string(), content="123")
  b.merge!(c)
  inspect!(c.to_string(), content="123")
}
