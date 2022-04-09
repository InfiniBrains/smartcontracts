// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

// Eth Heap
// Authors: Alexandre Tolstenko
// Original Author: Zac Mitton
// License: MIT
// ref.: https://github.com/zmitton/eth-heap/blob/master/contracts/Heap.sol

library Heap { // default max-heap
  uint constant ROOT_INDEX = 1;

  struct Data {
    int128 idCount;
    Node[] nodes; // root is index 1; index 0 not used
    mapping (int128 => uint) indices; // unique id => node index
  }
  struct Node{
    int128 id; //use with another mapping to store arbitrary object types
    int128 priority;
  }

  //call init before anything else
  function init(Data storage self) internal{
    if(self.nodes.length == 0) self.nodes.push(Node(0,0));
  }

  function insert(Data storage self, int128 priority) internal returns(Node memory){//√
    if(self.nodes.length == 0){ init(self); }// test on-the-fly-init
    self.idCount++;
//    self.nodes.length++; // this is the old approach.
    self.nodes.push(Node(0,0)); // todo: check if it is really working

    Node memory n = Node(self.idCount, priority);
    _bubbleUp(self, n, self.nodes.length-1);
    return n;
  }
  function extractMax(Data storage self) internal returns(Node memory){//√
    return _extract(self, ROOT_INDEX);
  }
  function extractById(Data storage self, int128 id) internal returns(Node memory){//√
    return _extract(self, self.indices[id]);
  }

  //view
  function dump(Data storage self) internal view returns(Node[] memory){
    //note: Empty set will return `[Node(0,0)]`. uninitialized will return `[]`.
    return self.nodes;
  }
  // todo: check all the storage and memory usage. Probably we will edit the values of a given node
  function getById(Data storage self, int128 id) internal view returns(Node storage){
    return getByIndex(self, self.indices[id]);//test that all these return the emptyNode
  }
  function getByIndex(Data storage self, uint i) internal view returns(Node storage){
//    return self.nodes.length > i ? self.nodes[i] : Node(0,0); // old approach
    require(self.nodes.length > i, "Invalid index"); // todo: test this
    return self.nodes[i];
  }
  function getMax(Data storage self) internal view returns(Node storage){
    return getByIndex(self, ROOT_INDEX);
  }
  function size(Data storage self) internal view returns(uint){
    return self.nodes.length > 0 ? self.nodes.length-1 : 0;
  }
  function isNode(Node memory n) internal pure returns(bool){ return n.id > 0; }

  //private
  function _extract(Data storage self, uint i) private returns(Node memory){//√
    if(self.nodes.length <= i || i <= 0){ return Node(0,0); }

    Node memory extractedNode = self.nodes[i];
    delete self.indices[extractedNode.id];

    Node memory tailNode = self.nodes[self.nodes.length-1];
//    self.nodes.length--; // old approach
    self.nodes.pop(); // todo: test this

    if(i < self.nodes.length){ // if extracted node was not tail
      _bubbleUp(self, tailNode, i);
      _bubbleDown(self, self.nodes[i], i); // then try bubbling down
    }
    return extractedNode;
  }
  function _bubbleUp(Data storage self, Node memory n, uint i) private{//√
    if(i==ROOT_INDEX || n.priority <= self.nodes[i/2].priority){
      _insert(self, n, i);
    }else{
      _insert(self, self.nodes[i/2], i);
      _bubbleUp(self, n, i/2);
    }
  }
  function _bubbleDown(Data storage self, Node memory n, uint i) private{//
    uint length = self.nodes.length;
    uint cIndex = i*2; // left child index

    if(length <= cIndex){
      _insert(self, n, i);
    }else{
      Node memory largestChild = self.nodes[cIndex];

      if(length > cIndex+1 && self.nodes[cIndex+1].priority > largestChild.priority ){
        largestChild = self.nodes[++cIndex];// TEST ++ gets executed first here
      }

      if(largestChild.priority <= n.priority){ //TEST: priority 0 is valid! negative ints work
        _insert(self, n, i);
      }else{
        _insert(self, largestChild, i);
        _bubbleDown(self, n, cIndex);
      }
    }
  }

  function _insert(Data storage self, Node memory n, uint i) private{//√
    self.nodes[i] = n;
    self.indices[n.id] = i;
  }
}