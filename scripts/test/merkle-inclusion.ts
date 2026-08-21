import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { Barretenberg, UltraHonkBackend } from '@aztec/bb.js';
import { Noir } from '@noir-lang/noir_js';
import { computeMerkleRootFromPath, hashLeaf, hashPair, hashFields, splitValue, loadCompiledCircuit, type LeafPreimage } from './_shared.js';

const TREE_DEPTH = 8;
const LEAF_COUNT = 1 << TREE_DEPTH;

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = resolve(__dirname, '..', '..');
const artifactPath = resolve(projectRoot, 'circuit', 'target', 'circuit.json');

type V2Case = {
  action_type: bigint;
  scope: bigint;
  expiry: bigint;
  value: bigint;
  master_agent_salt: bigint;
};

const v2Cases: V2Case[] = [
  { action_type: 7n, scope: 42n, expiry: 1_725_312_000n, value: 100n, master_agent_salt: 998_877n },
  { action_type: 11n, scope: 512n, expiry: 1_825_398_400n, value: 500n, master_agent_salt: 123_456n },
  { action_type: 255n, scope: 65_537n, expiry: 4_102_444_800n, value: 999_999_999n, master_agent_salt: 340_282_366_920_938_463_463_374_607_431_768_211_283n },
  { action_type: 3n, scope: 9_999n, expiry: 1_901_234_567n, value: 0n, master_agent_salt: 777_777n },
  { action_type: 91n, scope: 1_024n, expiry: 2_222_222_222n, value: 42_000n, master_agent_salt: 888_999n },
];

async function initLeaves(bb: Barretenberg): Promise<LeafPreimage[]> {
  const leaves: LeafPreimage[] = [];
  for (const v2case of v2Cases) {
    const { val_low, val_high } = splitValue(v2case.value);
    const leaf_salt = await hashFields(bb, [v2case.master_agent_salt, v2case.action_type, v2case.expiry]);
    leaves.push({
      action_type: v2case.action_type,
      scope: v2case.scope,
      expiry: v2case.expiry,
      val_low,
      val_high,
      leaf_salt,
    });
  }
  return leaves;
}

async function buildTree(bb: Barretenberg, leaves: bigint[]): Promise<bigint[][]> {
  let currentLevel = leaves;
  const levels = [currentLevel];

  for (let depth = 0; depth < TREE_DEPTH; depth += 1) {
    const nextLevel: bigint[] = [];

    for (let i = 0; i < currentLevel.length; i += 2) {
      nextLevel.push(await hashPair(bb, currentLevel[i], currentLevel[i + 1]));
    }

    levels.push(nextLevel);
    currentLevel = nextLevel;
  }

  return levels;
}

function getMerkleProof(levels: bigint[][], index: number): { path: bigint[]; indices: number[] } {
  const path: bigint[] = [];
  const indices: number[] = [];
  let currentIndex = index;

  for (let depth = 0; depth < TREE_DEPTH; depth += 1) {
    const siblingIndex = currentIndex ^ 1;
    path.push(levels[depth][siblingIndex]);
    indices.push(currentIndex & 1);
    currentIndex = Math.floor(currentIndex / 2);
  }

  return { path, indices };
}

async function expectNegativeCase(
  noir: Noir,
  policyRoot: bigint,
  rogueLeaf: LeafPreimage,
  rogueHash: bigint,
  path: bigint[],
  indices: number[],
): Promise<void> {
  try {
    await noir.execute({
      policy_root: policyRoot.toString(),
      action_hash: rogueHash.toString(),
      action_type: rogueLeaf.action_type.toString(),
      scope: rogueLeaf.scope.toString(),
      expiry: rogueLeaf.expiry.toString(),
      val_low: rogueLeaf.val_low.toString(),
      val_high: rogueLeaf.val_high.toString(),
      leaf_salt: rogueLeaf.leaf_salt.toString(),
      path: path.map((value) => value.toString()),
      indices,
    });
  } catch {
    console.log('NEGATIVE CASE CONFIRMED');
    return;
  }

  throw new Error('Negative case unexpectedly succeeded.');
}

async function main(): Promise<void> {
  const compiledCircuit = loadCompiledCircuit(artifactPath);
  const noir = new Noir(compiledCircuit);
  const bb = await Barretenberg.new();

  try {
    const policyLeaves = await initLeaves(bb);
    const leafHashes = await Promise.all(policyLeaves.map((leaf) => hashLeaf(bb, leaf)));
    const paddedLeaves = Array.from({ length: LEAF_COUNT }, (_, index) => leafHashes[index] ?? 0n);
    const levels = await buildTree(bb, paddedLeaves);
    const policyRoot = levels[TREE_DEPTH][0];

    const targetIndex = 3;
    const targetLeaf = policyLeaves[targetIndex];
    const actionHash = leafHashes[targetIndex];
    const { path, indices } = getMerkleProof(levels, targetIndex);
    const recomputedRoot = await computeMerkleRootFromPath(bb, actionHash, path, indices);

    if (recomputedRoot !== policyRoot) {
      throw new Error('TypeScript Merkle proof reconstruction did not match the computed policy root.');
    }

    const { witness } = await noir.execute({
      policy_root: policyRoot.toString(),
      action_hash: actionHash.toString(),
      action_type: targetLeaf.action_type.toString(),
      scope: targetLeaf.scope.toString(),
      expiry: targetLeaf.expiry.toString(),
      val_low: targetLeaf.val_low.toString(),
      val_high: targetLeaf.val_high.toString(),
      leaf_salt: targetLeaf.leaf_salt.toString(),
      path: path.map((value) => value.toString()),
      indices,
    });

    const backend = new UltraHonkBackend(compiledCircuit.bytecode, bb);
    const proof = await backend.generateProof(witness, { verifierTarget: 'noir-recursive' });
    const verified = await backend.verifyProof(proof, { verifierTarget: 'noir-recursive' });

    if (!verified) {
      throw new Error('Merkle inclusion proof failed local verification.');
    }

    console.log(`policy_root: ${policyRoot.toString()}`);
    console.log(`action_hash: ${actionHash.toString()}`);
    console.log('MERKLE INCLUSION CONFIRMED');

    const rogueCase: V2Case = {
      action_type: 404n,
      scope: 8080n,
      expiry: 3_333_333_333n,
      value: 12n,
      master_agent_salt: 919_191n,
    };
    const { val_low, val_high } = splitValue(rogueCase.value);
    const rogueLeaf: LeafPreimage = {
      action_type: rogueCase.action_type,
      scope: rogueCase.scope,
      expiry: rogueCase.expiry,
      val_low,
      val_high,
      leaf_salt: await hashFields(bb, [rogueCase.master_agent_salt, rogueCase.action_type, rogueCase.expiry]),
    };
    const rogueHash = await hashLeaf(bb, rogueLeaf);

    if (leafHashes.includes(rogueHash)) {
      throw new Error('Negative test leaf unexpectedly collided with the policy set.');
    }

    await expectNegativeCase(noir, policyRoot, rogueLeaf, rogueHash, path, indices);
  } finally {
    await bb.destroy();
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
