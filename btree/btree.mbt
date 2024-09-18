pub struct BTree[V] {
  mut root : BTreeNode[V]
  mut len : Int
  max_child_num : Int
}

// Update the `new` function to accept `max_child_num` as a parameter
pub fn new[V](~max_child_num : Int = 12) -> BTree[V] {
  BTree::{
    root: BTreeNode::Leaf({ entries: [], parent: None, len: 0 }),
    len: 0,
    max_child_num,
  }
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
  // Ensure current_index is within bounds
  if current_index > leaf.entries.length() {
    current_index = leaf.entries.length()
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
  if leaf.entries.length() >= self.max_child_num {
    let _ = cursor.path.pop()
    split_leaf(self, leaf, cursor.path)
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

pub impl[V : Show] Show for BTree[V] with output(
  self : BTree[V],
  logger : Logger
) -> Unit {
  node_to_string(self.root, 0, logger)
}

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

fn child_num[V](self : BTreeNode[V]) -> Int {
  match self {
    BTreeNode::Leaf(_) => 0
    BTreeNode::Node(node) => node.children.length()
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
  // Recalculate leaf.len after splitting
  leaf.len = sum(leaf.entries.iter().map(fn(e) { e.rle_len() }))
  let right_leaf = Leaf::{
    entries: right,
    len: sum(right.iter().map(fn(e) { e.rle_len() })),
    parent: leaf.parent,
  }
  match leaf.parent {
    Some(BTreeNode::Node(node)) => {
      let index = path[path.length() - 1].1
      node.children.insert(index + 1, BTreeNode::Leaf(right_leaf))
      if node.children.length() >= tree.max_child_num {
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
  // Recalculate node lengths
  node.len = sum(node.children.iter().map(fn(e) { e.len() }))
  right_node.len = sum(right_node.children.iter().map(fn(e) { e.len() }))
  match node.parent {
    Some(BTreeNode::Node(parent_node)) => {
      let index = path[path.length() - 1].1
      parent_node.children.insert(index + 1, BTreeNode::Node(right_node))
      if parent_node.children.length() >= tree.max_child_num {
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

fn repeat(s : String, n : Int) -> String {
  let mut result = ""
  for i = 0; i < n; i = i + 1 {
    result += s
  }
  result
}

fn indent(level : Int) -> String {
  repeat("  ", level)
}

fn node_to_string[V : Show](
  node : BTreeNode[V],
  level : Int,
  logger : Logger
) -> Unit {
  match node {
    BTreeNode::Leaf(leaf) => {
      let entries = leaf.entries.map(fn(v) { v.to_string() }).join(", ")
      logger.write_string(indent(level))
      logger.write_string("Leaf(len=")
      logger.write_string(leaf.len.to_string())
      logger.write_string("): [")
      logger.write_string(entries)
      logger.write_string("]")
    }
    BTreeNode::Node(inner_node) => {
      logger.write_string(indent(level) + "Node(len=\{inner_node.len}):")
      for child in inner_node.children {
        logger.write_string("\n")
        node_to_string(child, level + 1, logger)
      }
    }
  }
}

fn min(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

fn max(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

pub fn delete[V : Show + @rle.Rle](
  self : BTree[V],
  index : Int,
  len : Int
) -> Unit {
  if index < 0 || index + len > self.len {
    abort("index out of bounds. index: \{index}, len: \{self.len}")
  }
  let stack : Array[(BTreeNode[V], Int)] = []
  let mut current_node = self.root
  let mut current_index = 0
  // Traverse to the leaf node containing the start of the range
  while true {
    match current_node {
      BTreeNode::Leaf(_leaf) => {
        stack.push((current_node, 0))
        break
      }
      BTreeNode::Node(node) => {
        let mut child_index = 0
        while child_index < node.children.length() - 1 &&
              current_index + node.children[child_index].len() <= index {
          current_index += node.children[child_index].len()
          child_index += 1
        }
        stack.push((current_node, child_index))
        current_node = node.children[child_index]
      }
    }
  }
  let mut remaining_len = len
  while remaining_len > 0 && not(stack.is_empty()) {
    let (current_node, child_index) = stack.pop().unwrap()
    let mut current_node = current_node
    match current_node {
      BTreeNode::Leaf(leaf) => {
        let mut current_leaf_index = 0
        // Find the starting position in the leaf
        while current_index + leaf.entries[current_leaf_index].rle_len() <=
              index {
          current_index += leaf.entries[current_leaf_index].rle_len()
          current_leaf_index += 1
        }

        // Remove or split entries
        while remaining_len > 0 && current_leaf_index < leaf.entries.length() {
          let entry = leaf.entries[current_leaf_index]
          if current_index >= index &&
            current_index + entry.rle_len() <= index + remaining_len {
            // Remove entire entry because it is fully covered by the delete range
            ignore(leaf.entries.remove(current_leaf_index))
            remaining_len -= entry.rle_len()
            leaf.len -= entry.rle_len()
            current_index += entry.rle_len()
            // Do not increment current_leaf_index since entries have shifted
          } else {
            // Split entry
            let delete_start = max(index, current_index)
            let delete_end = min(index + len, current_index + entry.rle_len())
            let delete_len = delete_end - delete_start
            if delete_start > current_index &&
              delete_end < current_index + entry.rle_len() {
              // Remove the middle part and insert a new leaf node
              let left_len = delete_start - current_index
              let right_len = current_index + entry.rle_len() - delete_end
              let left_entry = entry.slice(0, left_len)
              let right_entry = entry.slice(
                entry.rle_len() - right_len,
                entry.rle_len(),
              )
              let _ = @expect.expect(entry.rle_len() - left_len - right_len).to_be(
                delete_len,
              )
              leaf.entries[current_leaf_index] = left_entry
              leaf.entries.insert(current_leaf_index + 1, right_entry)
              leaf.len -= delete_len
              current_leaf_index += 2
              current_index += left_len + right_len
            } else if delete_start > current_index {
              let left_len = min(delete_start - current_index, entry.rle_len())
              let actual_delete_len = entry.rle_len() - left_len
              // println(
              //   "\{delete_start} \{delete_end} \{delete_len} \{current_index} \{index} \{entry.rle_len()}",
              // )
              // println("\{left_len} \{actual_delete_len}")
              guard let Ok(_) = assert_eq?(actual_delete_len, delete_len)
              let left_entry = entry.slice(0, left_len)
              leaf.entries[current_leaf_index] = left_entry
              current_leaf_index += 1
            } else if delete_end > current_index &&
              delete_end < current_index + entry.rle_len() {
              // Right part remains
              let right_entry = entry.slice(
                delete_end - current_index,
                entry.rle_len(),
              )
              let actual_delete_len = delete_end - current_index
              let _ = @expect.expect(actual_delete_len).to_be(delete_len)
              leaf.entries[current_leaf_index] = right_entry
              current_leaf_index += 1
            } else {
              ignore(leaf.entries.remove(current_leaf_index))
              let _ = @expect.expect(entry.rle_len()).to_be(delete_len)

            }
            remaining_len -= delete_len
            leaf.len -= delete_len
            current_index += entry.rle_len() - delete_len
          }
        }

        // Check if we need to delete the node
        if leaf.entries.is_empty() {
          let stack = stack.copy()
          stack.push((current_node, child_index))
          delete_node(self, stack)
        }
        if leaf.entries.length() >= self.max_child_num {
          split_leaf(self, leaf, stack.copy())
        }
      }
      BTreeNode::Node(node) =>
        if child_index < node.children.length() - 1 {
          stack.push((current_node, child_index + 1))
          current_node = node.children[child_index + 1]
          stack.push((current_node, 0))
        }
    }
  }

  // Update lengths
  for node in stack {
    match node.0 {
      BTreeNode::Node(inner_node) => inner_node.len -= len
      _ => ()
    }
  }
  self.len -= len
}

fn delete_node[V : @rle.Rle](
  self : BTree[V],
  path : Array[(BTreeNode[V], Int)]
) -> Unit {
  if path.length() == 0 {
    abort("delete empty path")
  }
  if path.length() == 1 {
    guard let Ok(_) = assert_true?(physical_equal(path[0].0, self.root))
    return
  }
  // Remove the node from its parent using the index from the path
  let parent_index = path[path.length() - 1].1
  match path[path.length() - 2].0 {
    BTreeNode::Node(parent_node) => {
      ignore(parent_node.children.remove(parent_index))
      // Check if parent needs to handle lack
      if parent_node.children.length() < self.max_child_num / 2 {
        ignore(path.pop())
        handle_lack(self, parent_node, path)
      }
    }
    _ => abort("Parent is not a node")
  }
}

fn handle_lack[V : @rle.Rle](
  tree : BTree[V],
  node : Node[V],
  path : Array[(BTreeNode[V], Int)]
) -> Unit {
  let index = path[path.length() - 1].1
  guard let BTreeNode::Node(parent) = path[path.length() - 1].0
  if parent.children.length() <= 1 {
    return
  }
  let threshold = tree.max_child_num / 2
  // Try to borrow from left sibling
  if index > 0 && parent.children[index - 1].child_num() > threshold {
    borrow_from_sibling(tree, node, index - 1, true)
    return
  }

  // Try to borrow from right sibling
  if index < node.children.length() &&
    node.children[index].child_num() > threshold {
    borrow_from_sibling(tree, node, index, false)
    return
  }

  // Merge with left sibling if possible
  if index > 0 {
    merge_with_sibling(tree, node, index - 1, true, path)
    return
  }
  // Merge with right sibling
  merge_with_sibling(tree, node, index, false, path)
}

fn borrow_from_sibling[V : @rle.Rle](
  _tree : BTree[V],
  parent_node : Node[V],
  sibling_index : Int,
  is_left : Bool
) -> Unit {
  if is_left {
    let sibling = parent_node.children[sibling_index]
    let child = parent_node.children[sibling_index + 1]
    match (sibling, child) {
      (BTreeNode::Node(sibling_node), BTreeNode::Node(child_node)) => {
        // Move the last child from sibling to child
        let borrowed = sibling_node.children.pop().unwrap()
        child_node.children.insert(0, borrowed)
        borrowed.set_parent(Some(BTreeNode::Node(child_node)))
        // Update lengths
        sibling_node.len -= borrowed.len()
        child_node.len += borrowed.len()
      }
      (BTreeNode::Leaf(sibling_leaf), BTreeNode::Leaf(child_leaf)) => {
        // Move the last entry from sibling to child
        let borrowed = sibling_leaf.entries.pop().unwrap()
        child_leaf.entries.insert(0, borrowed)
        // Update lengths
        sibling_leaf.len -= borrowed.rle_len()
        child_leaf.len += borrowed.rle_len()
      }
      _ => abort("Mismatched node types")
    }
  } else {
    let sibling = parent_node.children[sibling_index + 1]
    let child = parent_node.children[sibling_index]
    match (sibling, child) {
      (BTreeNode::Node(sibling_node), BTreeNode::Node(child_node)) => {
        // Move the first child from sibling to child
        let borrowed = sibling_node.children.remove(0)
        child_node.children.push(borrowed)
        borrowed.set_parent(Some(BTreeNode::Node(child_node)))
        // Update lengths
        sibling_node.len -= borrowed.len()
        child_node.len += borrowed.len()
      }
      (BTreeNode::Leaf(sibling_leaf), BTreeNode::Leaf(child_leaf)) => {
        // Move the first entry from sibling to child
        let borrowed = sibling_leaf.entries.remove(0)
        child_leaf.entries.push(borrowed)
        // Update lengths
        sibling_leaf.len -= borrowed.rle_len()
        child_leaf.len += borrowed.rle_len()
      }
      _ => abort("Mismatched node types")
    }
  }
}

fn merge_with_sibling[V : @rle.Rle](
  tree : BTree[V],
  parent_node : Node[V],
  sibling_index : Int,
  is_left : Bool,
  path : Array[(BTreeNode[V], Int)]
) -> Unit {
  if is_left {
    let left = parent_node.children[sibling_index]
    let right = parent_node.children[sibling_index + 1]
    match (left, right) {
      (BTreeNode::Node(left_node), BTreeNode::Node(right_node)) => {
        // Merge right into left
        left_node.children.append(right_node.children)
        for child in right_node.children {
          child.set_parent(Some(BTreeNode::Node(left_node)))
        }
        left_node.len += right_node.len
      }
      (BTreeNode::Leaf(left_leaf), BTreeNode::Leaf(right_leaf)) => {
        // Merge right into left
        left_leaf.entries.append(right_leaf.entries)
        left_leaf.len += right_leaf.len
      }
      _ => abort("Mismatched node types")
    }
    ignore(parent_node.children.remove(sibling_index + 1))
  } else {
    let left = parent_node.children[sibling_index]
    let right = parent_node.children[sibling_index + 1]
    match (left, right) {
      (BTreeNode::Node(left_node), BTreeNode::Node(right_node)) => {
        // Merge left into right
        let children = left_node.children.copy()
        children.append(right_node.children)
        right_node.children = children
        for child in left_node.children {
          child.set_parent(Some(BTreeNode::Node(right_node)))
        }
        right_node.len += left_node.len
      }
      (BTreeNode::Leaf(left_leaf), BTreeNode::Leaf(right_leaf)) => {
        // Merge left into right
        let entries = left_leaf.entries.copy()
        entries.append(right_leaf.entries)
        right_leaf.entries = entries
        right_leaf.len += left_leaf.len
      }
      _ => abort("Mismatched node types")
    }
    ignore(parent_node.children.remove(sibling_index))
  }
  // After merging, check if parent needs to handle lack
  if parent_node.children.length() < tree.max_child_num / 2 {
    // Recursive call to handle lack on parent
    match parent_node.parent {
      Some(BTreeNode::Node(grandparent)) => {
        let _ = path.pop()
        handle_lack(tree, grandparent, path)
      }
      _ =>
        if parent_node.children.length() == 1 {
          // If the root node has only one child, make that child the new root
          tree.root = parent_node.children[0]
          tree.root.set_parent(None)
        }
    }
  }
}
