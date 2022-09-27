const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");
const ethers = require("ethers");
var seedrandom = require("seedrandom");

// Utility script to generate merkle trees/proofs for the tests
let addresses = [
  "0x5c90f12606a4b72374a7ed6dc84d5d10d7154cfb",
  "0x328d4c0306c6c6ee066309ec69d1cc7ce9641463",
  "0xfde4528d0bb3851c4032337b59d68c8075d2289f",
  "0xfea789d02772175912cf8433c779b0ca87a28739",
];

let period = 1;
let numberOfVaults = 2;
let decimals = [6, 18];

function printLeaf(leaf) {
  s = "[";
  for (x in leaf.amounts) {
    s = s + leaf.amounts[x].toString() + ",";
  }
  s = s.substring(0, s.length - 1) + "]";
  console.log(
    "Period:%d;Index:%d;Addr:%s,Amounts:%s",
    leaf.period,
    leaf.idx,
    leaf.addr,
    s
  );
}

function printPythonTestCode() {
  console.log("TEST_PERIOD = %d", period);
  s = "[";
  for (x in addresses) {
    s = s + '"' + addresses[x] + '",';
  }
  s = s.substring(0, s.length - 1) + "]";
  console.log("TEST_ADDRESSES = %s", s);

  s = "[";
  for (x in leaves) {
    s = s + "[";
    for (y in leaves[x].amounts) {
      s = s + leaves[x].amounts[y] + " ,";
    }
    s = s.substring(0, s.length - 1) + "],";
  }
  s = s.substring(0, s.length - 1) + "]";
  console.log("TEST_AMOUNTS = %s", s);
  s = "[";
  for (x in leavesHashed) {
    s = s + "[";
    let proofs = merkleTree.getHexProof(leavesHashed[x]);
    for (y in proofs) {
      s = s + '"' + proofs[y] + '",';
    }
    s = s.substring(0, s.length - 1) + "],";
  }
  s = s.substring(0, s.length - 1) + "]";
  console.log("TEST_PROOFS = %s", s);
  console.log('TEST_ROOT_HASH  = "%s"', rootHash.toString("hex"));
}

// for every address, setup amounts, period, index
const leaves = [];
let idx = 1;

//Pseudo number generator
var rng = seedrandom("test1");

for (addrIdx in addresses) {
  let addr = addresses[addrIdx];
  let amounts = [];
  for (let i = 0; i < numberOfVaults; i++) {
    x = ethers.BigNumber.from(10);
    x = x.pow(decimals[i] - 1); // Rewards are at most 1 whole unit (10^decimals[i])
    amounts.push(x.mul(Math.floor(rng() * 10)));
  }
  leaves.push({ period, idx, addr, amounts });
  idx++;
}
console.log(leaves);

let leavesEncoded = leaves.map((x) =>
  ethers.utils.defaultAbiCoder.encode(
    ["uint256", "uint256", "address", "uint256[]"],
    [x.period, x.idx, x.addr, x.amounts]
  )
);

console.log(leavesEncoded);

let leavesHashed = leavesEncoded.map((x) => keccak256(x));
console.log(leavesHashed);

for (x in leaves) {
  printLeaf(leaves[x]);
}
const merkleTree = new MerkleTree(leavesHashed, keccak256, {
  sortPairs: true,
});

const rootHash = merkleTree.getRoot();
console.log("Merkle tree\n", merkleTree.toString());

// Comparing hashes
console.log(
  keccak256(
    ethers.utils.defaultAbiCoder.encode(
      ["uint256", "uint256", "address", "uint256[]"],
      [1, 5000, "0xe7CB1c67752cBb975a56815Af242ce2Ce63d3113", [100, 199]]
    )
  )
);

printPythonTestCode();

// Generate proofs using
console.log(merkleTree.getHexProof(leavesHashed[0]));
