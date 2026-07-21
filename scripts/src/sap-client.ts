import { keccak256 } from 'js-sha3';
import { type Barretenberg } from '@aztec/bb.js';
import {
  hashFields,
  hashLeaf,
  hashPair,
  maskScope,
  splitValue,
  type LeafPreimage,
} from '../test/_shared.js';

export type ActionParams = {
  actionType: bigint;
  rawCalldata: Uint8Array | string;
  expiry: bigint;
  value: bigint;
  masterAgentSalt: bigint;
};

export class SAPClient {
  private bb: Barretenberg;

  constructor(bb: Barretenberg) {
    this.bb = bb;
  }

  public async createLeafPreimage(params: ActionParams): Promise<LeafPreimage> {
    const calldataBytes = typeof params.rawCalldata === 'string'
      ? Buffer.from(params.rawCalldata.replace(/^0x/, ''), 'hex')
      : params.rawCalldata;

    const rawKeccak = BigInt(`0x${keccak256(calldataBytes)}`);
    const scope = maskScope(rawKeccak);

    const { val_low, val_high } = splitValue(params.value);

    const leaf_salt = await hashFields(this.bb, [
      params.masterAgentSalt,
      params.actionType,
      params.expiry,
    ]);

    return {
      action_type: params.actionType,
      scope,
      expiry: params.expiry,
      val_low,
      val_high,
      leaf_salt,
    };
  }

  public async buildMerkleTree(leaves: LeafPreimage[], treeDepth: number = 8): Promise<{
    root: bigint;
    levels: bigint[][];
    leafHashes: bigint[];
  }> {
    const leafHashes = await Promise.all(leaves.map((leaf) => hashLeaf(this.bb, leaf)));
    const totalCapacity = 1 << treeDepth;
    const paddedLeaves = Array.from({ length: totalCapacity }, (_, idx) => leafHashes[idx] ?? 0n);

    let currentLevel = paddedLeaves;
    const levels = [currentLevel];

    for (let depth = 0; depth < treeDepth; depth += 1) {
      const nextLevel: bigint[] = [];
      for (let i = 0; i < currentLevel.length; i += 2) {
        nextLevel.push(await hashPair(this.bb, currentLevel[i], currentLevel[i + 1]));
      }
      levels.push(nextLevel);
      currentLevel = nextLevel;
    }

    const root = levels[treeDepth][0];
    return { root, levels, leafHashes };
  }

  public getMerkleProof(levels: bigint[][], index: number, treeDepth: number = 8): { path: bigint[]; indices: number[] } {
    const path: bigint[] = [];
    const indices: number[] = [];
    let currentIndex = index;

    for (let depth = 0; depth < treeDepth; depth += 1) {
      const siblingIndex = currentIndex ^ 1;
      path.push(levels[depth][siblingIndex]);
      indices.push(currentIndex & 1);
      currentIndex = Math.floor(currentIndex / 2);
    }

    return { path, indices };
  }
}
