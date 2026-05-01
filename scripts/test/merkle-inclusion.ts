import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { Barretenberg, UltraHonkBackend, fieldToString } from '@aztec/bb.js';
import { Noir } from '@noir-lang/noir_js';
import type { CompiledCircuit } from '@noir-lang/types';

type PolicyLeaf = {
  action_type: bigint;
  scope: bigint;
  expiry: bigint;
  agent_salt: bigint;
};

const TREE_DEPTH = 8;
const LEAF_COUNT = 1 << TREE_DEPTH;

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = resolve(__dirname, '..', '..');
const artifactPath = resolve(projectRoot, 'circuit', 'target', 'circuit.json');

const policyLeaves: PolicyLeaf[] = [
  { action_type: 7n, scope: 42n, expiry: 1_725_312_000n, agent_salt: 998_877_665_544_332_211n },
  { action_type: 11n, scope: 512n, expiry: 1_825_398_400n, agent_salt: 1_234_567_890_123_456_789n },
  { action_type: 255n, scope: 65_537n, expiry: 4_102_444_800n, agent_salt: 340_282_366_920_938_463_463_374_607_431_768_211_283n },
  { action_type: 3n, scope: 9_999n, expiry: 1_901_234_567n, agent_salt: 7_777_777_777_777_777n },
  { action_type: 91n, scope: 1_024n, expiry: 2_222_222_222n, agent_salt: 888_999_000_111_222_333n },
];

function toFieldBytes(value: bigint): Uint8Array {
  if (value < 0n) {
    throw new Error(`Field values must be non-negative. Received ${value.toString()}.`);
  }

  const hex = value.toString(16);
  if (hex.length > 64) {
    throw new Error(`Field value exceeds 32 bytes: ${value.toString()}`);
  }

  const padded = hex.padStart(64, '0');
  const bytes = new Uint8Array(32);

  for (let i = 0; i < 32; i += 1) {
    const offset = i * 2;
    bytes[i] = Number.parseInt(padded.slice(offset, offset + 2), 16);
  }

  return bytes;
}

async function hashFields(bb: Barretenberg, fields: bigint[]): Promise<bigint> {
  const result = await bb.poseidon2Hash({ inputs: fields.map(toFieldBytes) });
  return BigInt(fieldToString(result.hash));
}

async function hashLeaf(bb: Barretenberg, leaf: PolicyLeaf): Promise<bigint> {
  return hashFields(bb, [leaf.action_type, leaf.scope, leaf.expiry, leaf.agent_salt]);
}

async function hashPair(bb: Barretenberg, left: bigint, right: bigint): Promise<bigint> {
  return hashFields(bb, [left, right]);
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
  rogueLeaf: PolicyLeaf,
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
      agent_salt: rogueLeaf.agent_salt.toString(),
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
  const compiledCircuit = JSON.parse(readFileSync(artifactPath, 'utf8')) as CompiledCircuit;
  const noir = new Noir(compiledCircuit);
  const bb = await Barretenberg.new();

  try {
    const leafHashes = await Promise.all(policyLeaves.map((leaf) => hashLeaf(bb, leaf)));
    const paddedLeaves = Array.from({ length: LEAF_COUNT }, (_, index) => leafHashes[index] ?? 0n);
    const levels = await buildTree(bb, paddedLeaves);
    const policyRoot = levels[TREE_DEPTH][0];

    const targetIndex = 3;
    const targetLeaf = policyLeaves[targetIndex];
    const actionHash = leafHashes[targetIndex];
    const { path, indices } = getMerkleProof(levels, targetIndex);

    const { witness } = await noir.execute({
      policy_root: policyRoot.toString(),
      action_hash: actionHash.toString(),
      action_type: targetLeaf.action_type.toString(),
      scope: targetLeaf.scope.toString(),
      expiry: targetLeaf.expiry.toString(),
      agent_salt: targetLeaf.agent_salt.toString(),
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

    const rogueLeaf: PolicyLeaf = {
      action_type: 404n,
      scope: 8080n,
      expiry: 3_333_333_333n,
      agent_salt: 919_191_919_191_919_191n,
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
