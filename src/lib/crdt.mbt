pub struct Crdt {
  peer : Int64
  mut next_lamport : Int
  ops : Map[Int64, Array[Op]]
  state : Array[Op]
  deleted_by : Map[Id, @sorted_set.T[Id]]
  pending : Map[Id, Array[Op]]
  mut len : Int
}

struct Op {
  id : Id
  lamport : Int
  content : OpContent
} derive(Show, Eq, ToJson, FromJson)

fn idlp(self : Op) -> IdLp {
  IdLp::{ lamport: self.lamport, peer: self.id.peer }
}

enum OpContent {
  Insert(~origin_left : Id?, ~value : Char)
  Delete(Id)
} derive(Show, Eq, ToJson, FromJson)

pub struct IdLp {
  lamport : Int
  peer : Int64
} derive(Show, Eq, Compare, ToJson, FromJson, Hash)

pub struct Id {
  peer : Int64
  counter : Int
} derive(Show, Eq, ToJson, Compare, FromJson, Hash)

pub fn Crdt::new(peer : Int64) -> Crdt {
  Crdt::{
    peer,
    next_lamport: 0,
    ops: Map::new(),
    state: Array::new(),
    deleted_by: Map::new(),
    pending: Map::new(),
    len: 0,
  }
}

pub fn export_from(self : Crdt, vv : Map[Int64, Int]) -> Json {
  let ops : Array[Op] = Array::new()
  for p, p_ops in self.ops {
    if p_ops.is_empty() {
      continue
    }
    let counter_start = vv.get(p).or_default()
    if counter_start >= p_ops.length() {
      continue
    }
    for i = p_ops.length() - 1; i >= 0; i = i - 1 {
      let op = p_ops[i]
      if op.id.counter < counter_start {
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
  ops.sort_by_key(fn(x) { x.lamport })
  for op in ops {
    let id = op.id
    match self.ops.get(id.peer) {
      Some(x) => if x.length() > id.counter { continue }
      None => ()
    }
    self.apply_op(op)
  }
}

fn get_dep_of_op(op : Op) -> Id? {
  match op.content {
    Insert(~origin_left, ..) => origin_left
    Delete(id) => Some(id)
  }
}

fn include_id(self : Crdt, id : Id) -> Bool {
  self.ops.get(id.peer).map(fn(ops) { ops.length() > id.counter }).or(false)
}

fn check_whether_all_deps_met(self : Crdt, op : Op) -> Bool {
  let id = op.id
  if id.counter != 0 {
    if not(self.include_id({ peer: id.peer, counter: id.counter - 1 })) {
      self.pending
      .get_or_init(
        { peer: id.peer, counter: id.counter - 1 },
        fn() { Array::new() },
      )
      .push(op)
      return false
    }
  }
  match get_dep_of_op(op) {
    Some(dep) =>
      if not(self.include_id(dep)) {
        self.pending.get_or_init(dep, fn() { Array::new() }).push(op)
        return false
      }
    None => ()
  }
  true
}

fn apply_op(self : Crdt, op : Op) -> Unit {
  let id = op.id
  if not(self.check_whether_all_deps_met(op)) {
    return
  }
  self.ops.get_or_init(id.peer, fn() { Array::new() }).push(op)
  self.next_lamport = max(self.next_lamport, op.lamport + 1)
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
        if op.idlp() > self.state[i].idlp() {
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
  match self.pending.get(id) {
    Some(ops) => {
      self.pending.remove(id)
      for op in ops {
        self.apply_op(op)
      }
    }
    None => ()
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
  let counter = self.ops.get_or_init(self.peer, fn() { Array::new() }).length()
  let op = Op::{
    id: Id::{ counter, peer: self.peer },
    lamport,
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
    let counter = self.ops
      .get_or_init(self.peer, fn() { Array::new() })
      .length()
    self.deleted_by
    .get_or_init(op.id, fn() { @sorted_set.new() })
    .add(Id::{ counter, peer: self.peer })
    let delete_op = Op::{
      id: Id::{ counter, peer: self.peer },
      lamport,
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
    ans.set(p, ops.length())
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
