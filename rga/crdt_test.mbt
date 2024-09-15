test "basic insert delete" {
  let crdt = @rga.Crdt::new(0)
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
  let id0 = @rga.IdLp::{ lamport: 2, peer: 0 }
  let id1 = @rga.IdLp::{ lamport: 0, peer: 2 }
  assert_true!(id0 > id1)
}

test "merge" {
  let a = @rga.Crdt::new(0)
  let b = @rga.Crdt::new(1)
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

test "merge 1" {
  let a = @rga.Crdt::new(0)
  let b = @rga.Crdt::new(1)
  let c = @rga.Crdt::new(2)
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

test "merge 2" {
  let a = @rga.Crdt::new(0)
  let b = @rga.Crdt::new(1)
  let c = @rga.Crdt::new(2)

  // Initial inserts
  a.insert_str!(0, "Hello")
  b.insert_str!(0, "World")
  c.insert_str!(0, "CRDT")

  // First round of merges
  a.merge!(b)
  b.merge!(c)
  c.merge!(a)
  assert_eq!(a.to_string(), "CRDTWorldHello")
  assert_eq!(b.to_string(), "CRDTWorldHello")
  assert_eq!(c.to_string(), "CRDTWorldHello")

  // Concurrent edits
  a.delete!(0, len=2) // Delete "CR"
  b.insert_str!(4, " Sync ") // Insert " Sync" after "CRDT"
  c.delete!(9, len=5) // Delete "Hello"

  // Second round of merges
  a.merge!(b)
  b.merge!(c)
  c.merge!(a)
  let expected = "DT Sync World"
  assert_eq!(a.to_string(), expected)
  assert_eq!(b.to_string(), expected)
  assert_eq!(c.to_string(), expected)

  // More concurrent edits
  a.insert_str!(0, "Complex ")
  b.delete!(3, len=5) // Delete " Sync"
  c.insert_str!(c.length(), "!")

  // Final round of merges
  a.merge!(b)
  b.merge!(c)
  c.merge!(a)
  let final_expected = "Complex DT World!"
  assert_eq!(a.to_string(), final_expected)
  assert_eq!(b.to_string(), final_expected)
  assert_eq!(c.to_string(), final_expected)
}

test "complex sync scenario" {
  let a = @rga.Crdt::new(0)
  let b = @rga.Crdt::new(1)
  let c = @rga.Crdt::new(2)

  // Initial insertions
  a.insert_str!(0, "Hello")
  b.insert_str!(0, "World")
  c.insert_str!(0, "CRDT")

  // Partial sync
  a.merge!(b)
  b.merge!(c)

  // More modifications
  a.insert_str!(5, " there")
  inspect!(b.to_string(), content="CRDTWorldHello")
  b.delete!(0, len=3)
  inspect!(b.to_string(), content="TWorldHello")
  c.insert_str!(2, "awesome ")

  // Another partial sync
  a.merge!(c)
  b.merge!(a)

  // Final modifications
  inspect!(a.to_string(), content="awesome TWorld thereHello")
  a.delete!(6, len=5)
  inspect!(a.to_string(), content="awesomrld thereHello")
  b.insert_str!(b.length(), "!")
  c.insert_str!(0, "An ")

  // Final sync
  a.merge!(b)
  b.merge!(c)
  c.merge!(a)

  // Assertions
  inspect!(a.to_string(), content="An awesomrld thereHello!")
  inspect!(b.to_string(), content="An awesomrld thereHello!")
  inspect!(c.to_string(), content="An awesomrld thereHello!")
  assert_eq!(a.to_string(), "An awesomrld thereHello!")
  assert_eq!(b.to_string(), "An awesomrld thereHello!")
  assert_eq!(c.to_string(), "An awesomrld thereHello!")
  assert_eq!(a.length(), "An awesomrld thereHello!".length())
  assert_eq!(b.length(), "An awesomrld thereHello!".length())
  assert_eq!(c.length(), "An awesomrld thereHello!".length())
}

test "need pending" {
  let a = @rga.Crdt::new(0)
  let b = @rga.Crdt::new(1)
  a.insert_str!(0, "123")
  b.insert_str!(0, "abc")
  b.apply!(a.export_from({ 0: 1 }))
  b.apply!(a.export_from({ 0: 0 }))
  a.apply!(b.export_from({}))
  assert_eq!(a.to_string(), "abc123")
  assert_eq!(b.to_string(), "abc123")
}

test "random ops" {
  let rand = @random.Rand::new()
  let num_peers = 5
  let num_ops = 1000
  let crdts = Array::new()
  for i = 0; i < num_peers; i = i + 1 {
    crdts.push(@rga.Crdt::new(i.to_int64()))
  }
  for k = 0; k < num_ops; k = k + 1 {
    let peer_index = rand.int(limit=num_peers)
    let crdt = crdts[peer_index]
    let op_type = rand.int(limit=3)
    match op_type {
      0 => {
        // Insert
        let pos = rand.int(limit=crdt.length() + 1)
        let char = Char::from_int(rand.int(limit=26) + 'a'.to_int())
        crdt.insert!(pos, char)
      }
      1 =>
        // Delete
        if crdt.length() > 0 {
          let pos = rand.int(limit=crdt.length())
          let len = rand.int(limit=min(5, crdt.length() - pos)) + 1
          crdt.delete!(pos, ~len)
        }
      2 => {
        // Merge
        let other_index = rand.int(limit=num_peers)
        if other_index != peer_index {
          crdt.merge!(crdts[other_index])
        }
      }
      _ => abort("Unexpected op type")
    }
  }

  // Final merge
  for i = 1; i < num_peers; i = i + 1 {
    crdts[0].merge!(crdts[i])
  }
  for i = 1; i < num_peers; i = i + 1 {
    crdts[0].merge!(crdts[i])
  }

  // Assert all CRDTs have the same content
  let final_content = crdts[0].to_string()
  let final_length = crdts[0].length()
  for crdt in crdts {
    assert_eq!(crdt.to_string(), final_content)
    assert_eq!(crdt.length(), final_length)
  }
}

fn min[T : Compare](a : T, b : T) -> T {
  if a < b {
    a
  } else {
    b
  }
}
