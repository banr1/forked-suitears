import { sha3_256 } from 'js-sha3';
import { MerkleTree } from 'merkletreejs';

import { bcs } from '@mysten/sui.js/bcs';

export const createTree = () => {
  const ADDRESS_ALICE =
    '0x94fbcf49867fd909e6b2ecf2802c4b2bba7c9b2d50a13abbb75dbae0216db82a';

  const AMOUNT_ALICE = 55;

  const ADDRESS_BOB =
    '0xb4536519beaef9d9207af2b5f83ae35d4ac76cc288ab9004b39254b354149d27';

  const AMOUNT_BOB = 27;

  const DATA_ONE = Buffer.concat([
    Buffer.from(bcs.ser(bcs.Address.name, ADDRESS_ALICE).toBytes()),
    Buffer.from(bcs.ser(bcs.u64.name, AMOUNT_ALICE).toBytes()),
  ]);

  const DATA_TWO = Buffer.concat([
    Buffer.from(bcs.ser(bcs.Address.name, ADDRESS_BOB).toBytes()),
    Buffer.from(bcs.ser(bcs.u64.name, AMOUNT_BOB).toBytes()),
  ]);

  const leaves = [DATA_ONE, DATA_TWO].map((x) => sha3_256(x));

  const tree = new MerkleTree(leaves, sha3_256, { sortPairs: true });
  const root = tree.getHexRoot();

  const leaf = sha3_256(DATA_ONE);
  const proof = tree.getHexProof(leaf);
  const leaf2 = sha3_256(DATA_TWO);
  const proof2 = tree.getHexProof(leaf2);

  const wrongLeaf = sha3_256(
    Buffer.concat([
      Buffer.from(bcs.ser(bcs.Address.name, ADDRESS_BOB).toBytes()),
      Buffer.from(bcs.ser(bcs.u64.name, AMOUNT_BOB + 1).toBytes()),
    ]),
  );

  const wrongProof = tree.getHexProof(wrongLeaf);

  console.log({
    DATA_ONE,
    root,
    leaf,
    proof,
    leaf2,
    proof2,
    wrongLeaf,
    wrongProof,
  });
};
