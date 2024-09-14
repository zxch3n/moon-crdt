pub struct Crdt {
  peer : Int64
  mut next_lamport : Int
  ops : Map[Int64, Array[Op]]
  state : Array[Op]
  deleted_by : Map[Id, @sorted_set.T[Id]]
  mut len : Int
}

struct Op {
  id : Id
  content : OpContent
} derive(Show, Eq, ToJson, FromJson)

enum OpContent {
  Insert(~origin_left : Id?, ~value : Char)
  Delete(Id)
} derive(Show, Eq, ToJson, FromJson)

pub struct Id {
  lamport : Int
  peer : Int64
} derive(Show, Eq, Compare, ToJson, FromJson, Hash)

pub fn Crdt::new(peer : Int64) -> Crdt {
  Crdt::{
    peer,
    next_lamport: 0,
    ops: Map::new(),
    state: Array::new(),
    deleted_by: Map::new(),
    len: 0,
  }
}

pub fn export_from(self : Crdt, vv : Map[Int64, Int]) -> Json {
  let ops : Array[Op] = Array::new()
  for p, p_ops in self.ops {
    if p_ops.is_empty() {
      continue
    }
    let lamport_start = vv.get(p).or_default()
    if lamport_start >= p_ops.last().unwrap().id.lamport {
      continue
    }
    for i = p_ops.length() - 1; i >= 0; i = i - 1 {
      let op = p_ops[i]
      if op.id.lamport < lamport_start {
        break
      }
      ops.push(op)
    }
  }
  ops.to_json()
}

pub type! ApplyError {
  BrokenData
}

fn max[T : Compare](a : T, b : T) -> T {
  if a > b {
    a
  } else {
    b
  }
}

/// Currently, it doesn't handle pending operations.
/// We assume all ops are either appliable or applied.
pub fn apply(self : Crdt, json : Json) -> Unit!Error {
  let ops : Array[Op] = @json.from_json!(json)
  ops.sort_by_key(fn(x) { x.id.lamport })
  for op in ops {
    let id = op.id
    match self.ops.get(id.peer) {
      Some(x) => if x.last().unwrap().id.lamport >= id.lamport { continue }
      None => ()
    }
    self.apply_op(op)
  }
}

fn apply_op(self : Crdt, op : Op) -> Unit {
  let id = op.id
  self.next_lamport = max(self.next_lamport, id.lamport + 1)
  self.ops.get_or_init(id.peer, fn() { Array::new() }).push(op)
  match op.content {
    Insert(~origin_left, ..) => {
      let mut left_index = -1
      match origin_left {
        None => ()
        Some(left) =>
          for i, op in self.state.iter2() {
            if op.id == left {
              left_index = i
              break
            }
          }
      }
      let mut i = left_index + 1
      while i < self.state.length() {
        if op.id > self.state[i].id {
          break
        }
        i = i + 1
      }
      self.state.insert(i, op)
      self.len += 1
    }
    Delete(id) => {
      let set = self.deleted_by.get_or_init(id, fn() { @sorted_set.new() })
      if set.is_empty() {
        self.len -= 1
      }
      set.add(op.id)
    }
  }
}

pub type! OutOfRange String

pub fn insert_str(self : Crdt, pos : Int, s : String) -> Unit!OutOfRange {
  let mut pos = pos
  for c in s {
    self.insert!(pos, c)
    pos = pos + 1
  }
}

pub fn insert(self : Crdt, pos : Int, c : Char) -> Unit!OutOfRange {
  if pos > self.len || pos < 0 {
    raise OutOfRange(
      "pos \{pos} is out of range (Array.length: \{self.state.length()})",
    )
  }
  let index = self.get_pos_index(pos)
  let lamport = self.next_lamport
  self.next_lamport += 1
  let op = Op::{
    id: Id::{ lamport, peer: self.peer },
    content: OpContent::Insert(
      origin_left=self.state.get(index - 1).map(fn(op) { op.id }),
      value=c,
    ),
  }
  self.apply_op(op)
}

pub fn delete(self : Crdt, pos : Int, ~len : Int = 1) -> Unit!OutOfRange {
  if pos + len > self.len || pos < 0 {
    raise OutOfRange(
      "pos \{pos} + len \{len} is out of range (Array.length: \{self.state.length()})",
    )
  }
  let mut index = self.get_pos_index(pos)
  for i = pos; i < pos + len; i = i + 1 {
    let lamport = self.next_lamport
    self.next_lamport += 1
    let op = self.state[index]
    self.deleted_by
    .get_or_init(op.id, fn() { @sorted_set.new() })
    .add(Id::{ lamport, peer: self.peer })
    let delete_op = Op::{
      id: Id::{ lamport, peer: self.peer },
      content: OpContent::Delete(op.id),
    }
    self.ops.get_or_init(self.peer, fn() { Array::new() }).push(delete_op)
    index += 1
    while index < self.state.length() &&
          self.deleted_by.contains(self.state[index].id) {
      index += 1
    }
  }
  self.len -= len
  ()
}

fn get_pos_index(self : Crdt, pos : Int) -> Int {
  let mut cur_size = 0
  for i = 0; i < self.state.length(); i = i + 1 {
    let op = self.state[i]
    if not(self.deleted_by.contains(op.id)) {
      if cur_size == pos {
        return i
      }
      cur_size += 1
    }
  } else {
    self.state.length()
  }
}

pub fn to_string(self : Crdt) -> String {
  let f = fn(op : Op) {
    match op.content {
      Insert(~value, ..) =>
        if self.deleted_by.contains(op.id) {
          None
        } else {
          Some(value.to_string())
        }
      Delete(_) => panic()
    }
  }
  self.state.map_option(f).join("")
}

pub fn version(self : Crdt) -> Map[Int64, Int] {
  let ans = Map::new()
  for p, ops in self.ops {
    ans.set(p, ops.last().unwrap().id.lamport + 1)
  }
  ans
}

pub fn length(self : Crdt) -> Int {
  self.len
}

pub fn merge!(self : Crdt, other : Crdt) -> Unit {
  self.apply!(other.export_from(self.version()))
  other.apply!(self.export_from(other.version()))
  ()
}
