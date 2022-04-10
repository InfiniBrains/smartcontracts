// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

// Eth Heap
// Authors: Alexandre Tolstenko
// Original Author: Zac Mitton
// License: MIT
// ref.: https://github.com/zmitton/eth-heap/blob/master/contracts/Heap.sol
// ref.: https://github.com/zmitton/eth-heap/blob/master/contracts/OrderBookHeap.sol

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// todo: get node by timestamp
// todo: remove nodes older than a provided time

library Heap { // default max-heap
  using SafeMath for uint256;

  uint256 constant ROOT_INDEX = 1;

  struct Data{
    uint256 idCount;
    Node[] nodes; // root is index 1; index 0 not used
    mapping (uint256 => uint256) indices; // unique time => node index
  }
  struct Node{
    uint256 id;
    uint256 price;
    uint256 time;
  }

  //call init before anything else
  function init(Data storage self) internal{
    if(self.nodes.length == 0) self.nodes.push(Node(0,0,0));
  }

  function insert(Data storage self, uint256 price, uint256 time) internal returns(Node memory){//√
    if(self.nodes.length == 0){ init(self); }// test on-the-fly-init
    self.idCount++;
//    self.nodes.length++; // old approach
    self.nodes.push(Node(0,0,0));
    Node memory n = Node(self.idCount, price, time);
    _bubbleUp(self, n, self.nodes.length-1);
    return n;
  }
  function extractMax(Data storage self) internal returns(Node memory){//√
    return _extract(self, ROOT_INDEX);
  }
  function extractById(Data storage self, uint256 id) internal returns(Node memory){//√
    return _extract(self, self.indices[id]);
  }

  //view
  function dump(Data storage self) internal view returns(Node[] memory){
    //note: Empty set will return `[Node(0,0,0,0)]`. uninitialized will return `[]`.
    return self.nodes;
  }
  function getById(Data storage self, uint256 id) internal view returns(Node storage){
    return getByIndex(self, self.indices[id]);//test that all these return the emptyNode
  }
  function getByIndex(Data storage self, uint256 i) internal view returns(Node storage) {
    require(self.nodes.length > i, "index not found");
    // return self.nodes.length > i ? self.nodes[i] : Node(0,0,0,0); // old approach
    return self.nodes[i];
  }
  function getMax(Data storage self) internal view returns(Node storage){
    return getByIndex(self, ROOT_INDEX);
  }
  function size(Data storage self) internal view returns(uint256){
    return self.nodes.length > 0 ? self.nodes.length-1 : 0; // todo: is it really possible to be negative???
  }
  function isNode(Node memory n) internal pure returns(bool){ return n.id > 0; }

  //private
  function _extract(Data storage self, uint256 i) private returns(Node memory){//√
    if(self.nodes.length <= i || i <= 0){ return Node(0,0,0); }

    Node memory extractedNode = self.nodes[i];
    delete self.indices[extractedNode.id];

    Node memory tailNode = self.nodes[self.nodes.length-1];
    // self.nodes.length--; // old approach
    self.nodes.pop(); // updated approach todo: check this

    if(i < self.nodes.length){ // if extracted node was not tail
      _bubbleUp(self, tailNode, i);
      _bubbleDown(self, self.nodes[i], i); // then try bubbling down
    }
    return extractedNode;
  }
  function _bubbleUp(Data storage self, Node memory n, uint256 i) private{//√
    if(i==ROOT_INDEX || n.price <= self.nodes[i/2].price){
      _insert(self, n, i);
    }else{
      _insert(self, self.nodes[i/2], i);
      _bubbleUp(self, n, i/2);
    }
  }
  function _bubbleDown(Data storage self, Node memory n, uint256 i) private{//
    uint256 length = self.nodes.length;
    uint256 cIndex = i*2; // left child index

    if(length <= cIndex){
      _insert(self, n, i);
    }else{
      Node memory largestChild = self.nodes[cIndex];

      if(length > cIndex+1 && self.nodes[cIndex+1].price > largestChild.price ){
        largestChild = self.nodes[++cIndex];
      }

      if(largestChild.price <= n.price){
        _insert(self, n, i);
      }else{
        _insert(self, largestChild, i);
        _bubbleDown(self, n, cIndex);
      }
    }
  }

  // todo: check all functions using id
  function _insert(Data storage self, Node memory n, uint256 i) private{//√
    self.nodes[i] = n;
    self.indices[n.id] = i;
  }
}