const { MerkleTree } = require('merkletreejs')
const keccak256 = require('keccak256')
const ethers = require('ethers')

// Utility script to generate merkle trees/proofs for the tests
function printLeaf(leaf) {
  s = '['
  for (x in leaf.amounts) {
    s = s + leaf.amounts[x].toString() + ','
  }
  s = s.substring(0, s.length - 1) + ']'
  console.log(
    'Period:%d;Index:%d;Addr:%s,Amounts:%s',
    leaf.period,
    leaf.idx,
    leaf.addr,
    s,
  )
}
let addresses = [
  '0x5c90f12606a4b72374a7ed6dc84d5d10d7154cfb',
  '0x328d4c0306c6c6ee066309ec69d1cc7ce9641463',
  '0xfde4528d0bb3851c4032337b59d68c8075d2289f',
  '0xfea789d02772175912cf8433c779b0ca87a28739',
  '0xb4000b1c1bccecbb6a832e439293cdb38b35b6d9',
  '0x2c250ad4f86c3230f609e74a305028a2cedea4bf',
  '0xc214d6fb1b976ce87eabd0da55ccc12b46a8d46d',
  '0xb5520151323214b026887a895a99d74c96d2671e',
  '0x066ce56c5bc53b86d891dddfba19e1fcb6cf83b2',
  '0x51615876b128ec58ec208e7d19cb7cc813f2c2ea',
  '0x680262ab158675d561b933b225b998faa9b7721d',
  '0xf5bf6dcf2a6aa63ac4f5ba90a2cf2bfd83b67e77',
  '0x44e8c9a5a25fd6f69eab602a63c4bc5b0cc0b02d',
  '0xe82610f8e2cdc0a3cc90416e803d97de25bc0dbd',
  '0x7bb53a3af36ceab1358cbea3406ac560b872501f',
  '0xdfe7892d0e12d295252965ca426791b16d9f49e5',
  '0x596e3f4d8abada530cf14a5984c17f014d766f2a',
  '0x3ad4f5356fa66c43013e13ba59ced78bbf5c011d',
  '0xc56ed8eb068dc34b6ac05acd964cf288a3e86899',
  '0xba879850a990bd99247204872754864cea34ba9d',
]

let period = 3
let numberOfVaults = 2
let decimals = [6, 18]
// for every address, setup amounts, period, index
const leaves = []
let idx = 1
for (addrIdx in addresses) {
  let addr = addresses[addrIdx]
  let amounts = []
  for (let i = 0; i < numberOfVaults; i++) {
    x = ethers.BigNumber.from(10)
    x = x.pow(decimals[i])
    amounts.push(x.mul(Math.floor(Math.random() * 500)))
  }
  leaves.push({ period, idx, addr, amounts })
  idx++
}
console.log(leaves)

let leavesEncoded = leaves.map((x) =>
  ethers.utils.defaultAbiCoder.encode(
    ['uint256', 'uint256', 'address', 'uint256[]'],
    [x.period, x.idx, x.addr, x.amounts],
  ),
)

console.log(leavesEncoded)

let leavesHashed = leavesEncoded.map((x) => keccak256(x))
console.log(leavesHashed)

for (x in leaves) {
  printLeaf(leaves[x])
}
const merkleTree = new MerkleTree(leavesHashed, keccak256, { sortPairs: true })

const rootHash = merkleTree.getRoot()
console.log('Merkle tree\n', merkleTree.toString())

// Generate proofs using
const proof = merkleTree.getHexProof(leavesHashed[0])
console.log(proof)
