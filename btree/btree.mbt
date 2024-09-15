pub struct BTree[V] {
  mut root : BTreeNode[V]
  mut len : Int
}

let max_child_num : Int = 6

enum BTreeNode[V] {
  Leaf(Leaf[V])
  Node(Node[V])
}

fn len[V](self : BTreeNode[V]) -> Int {
  match self {
    BTreeNode::Leaf(leaf) => leaf.len
    BTreeNode::Node(node) => node.len
  }
}

fn set_parent[V](self : BTreeNode[V], parent : BTreeNode[V]?) -> Unit {
  match self {
    BTreeNode::Leaf(leaf) => leaf.parent = parent
    BTreeNode::Node(node) => node.parent = parent
  }
}

struct Leaf[V] {
  mut entries : Array[V]
  mut parent : BTreeNode[V]?
  mut len : Int
}

struct Node[V] {
  mut children : Array[BTreeNode[V]]
  mut parent : BTreeNode[V]?
  mut len : Int
}

pub struct Cursor[V] {
  path : Array[(BTreeNode[V], Int)]
  mut offset : Int
}

pub fn output[V](self : Cursor[V], logger : Logger) -> Unit {
  for a in self.path {
    logger.write_string("\{a.1}, ")
  }
  logger.write_string(" | \{self.offset}")
}

pub fn len[V](self : BTree[V]) -> Int {
  self.len
}

pub fn new[V]() -> BTree[V] {
  BTree::{
    root: BTreeNode::Leaf({ entries: [], parent: None, len: 0 }),
    len: 0,
  }
}

fn check_node_integrity![V : @rle.Rle](node : BTreeNode[V]) -> Int {
  match node {
    BTreeNode::Leaf(leaf) => {
      let calculated_len = sum(leaf.entries.iter().map(fn(e) { e.rle_len() }))
      assert_eq!(calculated_len, leaf.len)
      calculated_len
    }
    BTreeNode::Node(node) => {
      let mut calculated_len = 0
      for child in node.children {
        calculated_len += check_node_integrity!(child)
      }
      assert_eq!(calculated_len, node.len)
      calculated_len
    }
  }
}

pub fn check_integrity![V : @rle.Rle](self : BTree[V]) -> Unit!Error {
  let root_len = check_node_integrity!(self.root)
  assert_eq!(root_len, self.len)
}

pub fn query[V : @rle.Rle](self : BTree[V], index : Int) -> Cursor[V]? {
  if index < 0 || index > self.len {
    return None
  }
  let mut current_node = self.root
  let mut current_index = 0
  let path = Array::new()
  while true {
    match current_node {
      BTreeNode::Leaf(leaf) => {
        for i, entry in leaf.entries.iter2() {
          if current_index + entry.rle_len() > index {
            path.push((BTreeNode::Leaf(leaf), i))
            return Some(Cursor::{ path, offset: index - current_index })
          }
          current_index += entry.rle_len()
        }
        path.push((BTreeNode::Leaf(leaf), leaf.entries.length()))
        return Some(Cursor::{ path, offset: 0 })
      }
      BTreeNode::Node(node) =>
        for i, child_node in node.children.iter2() {
          let child_len = child_node.len()
          if current_index + child_len > index {
            path.push((BTreeNode::Node(node), i))
            current_node = child_node
            break
          }
          current_index += child_len
        } else {
          path.push((BTreeNode::Node(node), node.children.length() - 1))
          current_index -= node.children[node.children.length() - 1].len()
          current_node = node.children[node.children.length() - 1]
        }
    }
  }
  None
}

pub fn insert[V : @rle.Rle](self : BTree[V], index : Int, value : V) -> Unit {
  if index < 0 || index > self.len {
    abort("index out of bounds. index: \{index}, len: \{self.len}")
  }
  guard let Some(cursor) = self.query(index)
  let current_node = cursor.path.last().unwrap().0
  let mut current_index = cursor.path.last().unwrap().1
  let to_insert = value
  guard let BTreeNode::Leaf(leaf) = current_node
  if current_index < leaf.entries.length() &&
    cursor.offset == leaf.entries[current_index].rle_len() {
    cursor.offset = 0
    current_index += 1
  }
  if cursor.offset > 0 {
    // Split the existing entry
    let existing_entry = leaf.entries[current_index]
    let (left, right) = @rle.split(existing_entry, cursor.offset)
    leaf.entries[current_index] = left
    leaf.entries.insert(current_index + 1, right)
    current_index += 1
  }
  insert_value_to_leaf_with_merge(leaf, current_index, to_insert)
  for node in cursor.path {
    match node.0 {
      BTreeNode::Leaf(leaf) => leaf.len += to_insert.rle_len()
      BTreeNode::Node(node) => node.len += to_insert.rle_len()
    }
  }
  self.len += to_insert.rle_len()

  // Handle leaf splitting if necessary
  if leaf.entries.length() >= max_child_num {
    let _ = cursor.path.pop()
    split_leaf(self, leaf, cursor.path)
  }
}

fn insert_value_to_leaf_with_merge[V : @rle.Rle](
  leaf : Leaf[V],
  index : Int,
  value : V
) -> Unit {
  // Check if we can merge with the left element
  if index > 0 {
    let left_entry = leaf.entries[index - 1]
    if left_entry.can_merge(value) {
      leaf.entries[index - 1] = left_entry.merge(value)
      return
    }
  }

  // Check if we can merge with the right element
  if index < leaf.entries.length() {
    let right_entry = leaf.entries[index]
    if value.can_merge(right_entry) {
      leaf.entries[index] = value.merge(right_entry)
      return
    }
  }

  // Insert the new value
  leaf.entries.insert(index, value)
}

fn sum(iter : Iter[Int]) -> Int {
  let mut sum = 0
  for value in iter {
    sum += value
  }
  sum
}

fn split_leaf[V : @rle.Rle](
  tree : BTree[V],
  leaf : Leaf[V],
  path : Array[(BTreeNode[V], Int)]
) -> Unit {
  let mid = leaf.entries.length() / 2
  let (left, right) = leaf.entries.split_at(mid)
  leaf.entries = left
  let right_leaf = Leaf::{
    entries: right,
    len: sum(right.iter().map(fn(e) { e.rle_len() })),
    parent: leaf.parent,
  }
  leaf.len -= right_leaf.len
  match leaf.parent {
    Some(BTreeNode::Node(node)) => {
      let index = path[path.length() - 1].1
      node.children.insert(index + 1, BTreeNode::Leaf(right_leaf))
      if node.children.length() >= max_child_num {
        let _ = path.pop()
        split_node(tree, node, path)
      }
    }
    Some(BTreeNode::Leaf(_)) => abort("Parent should be a Node")
    None => {
      let new_root = Node::{
        children: [BTreeNode::Leaf(leaf), BTreeNode::Leaf(right_leaf)],
        parent: None,
        len: leaf.len + right_leaf.len,
      }
      tree.root = BTreeNode::Node(new_root)
      leaf.parent = Some(BTreeNode::Node(new_root))
      right_leaf.parent = Some(BTreeNode::Node(new_root))
    }
  }
}

fn split_node[V](
  tree : BTree[V],
  node : Node[V],
  path : Array[(BTreeNode[V], Int)]
) -> Unit {
  let mid = node.children.length() / 2
  let (left_children, right_children) = node.children.split_at(mid)
  node.children = left_children
  let right_node = Node::{
    len: 0,
    children: right_children,
    parent: node.parent,
  }
  for child in right_node.children {
    child.set_parent(Some(BTreeNode::Node(right_node)))
  }
  right_node.len = sum(right_node.children.iter().map(fn(e) { e.len() }))
  node.len = sum(node.children.iter().map(fn(e) { e.len() }))
  match node.parent {
    Some(BTreeNode::Node(parent_node)) => {
      let index = path[path.length() - 1].1
      parent_node.children.insert(index + 1, BTreeNode::Node(right_node))
      if parent_node.children.length() >= max_child_num {
        let _ = path.pop()
        split_node(tree, parent_node, path)
      }
    }
    Some(BTreeNode::Leaf(_)) => abort("Parent should be a Node")
    None => {
      let new_root = Node::{
        children: [BTreeNode::Node(node), BTreeNode::Node(right_node)],
        parent: None,
        len: node.len + right_node.len,
      }
      tree.root = BTreeNode::Node(new_root)
      node.parent = Some(BTreeNode::Node(new_root))
      right_node.parent = Some(BTreeNode::Node(new_root))
    }
  }
}

pub fn iter[V](self : BTree[V]) -> Iter[V] {
  Iter::new(
    fn(yield) {
      fn dfs(node : BTreeNode[V]) -> IterResult {
        match node {
          BTreeNode::Leaf(leaf) =>
            for value in leaf.entries {
              if yield(value) == IterEnd {
                return IterEnd
              }
            }
          BTreeNode::Node(inner_node) =>
            for child in inner_node.children {
              if dfs(child) == IterEnd {
                return IterEnd
              }
            }
        }
        IterContinue
      }

      dfs(self.root)
    },
  )
}

fn repeat(s : String, n : Int) -> String {
  let mut result = ""
  for i = 0; i < n; i = i + 1 {
    result += s
  }
  result
}

pub fn output[V : Show](self : BTree[V], logger : Logger) -> Unit {
  logger.write_string(node_to_string(self.root, 0))
}

pub fn to_string[V : Show](self : BTree[V]) -> String {
  node_to_string(self.root, 0)
}

fn indent(level : Int) -> String {
  repeat("  ", level)
}

fn node_to_string[V : Show](node : BTreeNode[V], level : Int) -> String {
  match node {
    BTreeNode::Leaf(leaf) => {
      let entries = leaf.entries.map(fn(v) { v.to_string() }).join(", ")
      indent(level) + "Leaf(len=\{leaf.len}): [" + entries + "]"
    }
    BTreeNode::Node(inner_node) => {
      let mut result = indent(level) + "Node(len=\{inner_node.len}):\n"
      for child in inner_node.children {
        result += node_to_string(child, level + 1) + "\n"
      }
      result.trim_right("\n")
    }
  }
}
