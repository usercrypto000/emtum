import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { Barretenberg, UltraHonkBackend, type VerifierTarget } from '@aztec/bb.js';
import { Noir } from '@noir-lang/noir_js';
import {
  bytesToHex,
  computeMerkleRootFromPath,
  fieldHexFromBigInt,
  hashLeaf,
  hashPair,
  loadCompiledCircuit,
  type LeafPreimage,
} from './_shared.js';

const TREE_DEPTH = 8;
const LEAF_COUNT = 1 << TREE_DEPTH;
const VERIFIER_TARGET: VerifierTarget = 'evm';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = resolve(__dirname, '..', '..');
const artifactPath = resolve(projectRoot, 'circuit', 'target', 'circuit.json');
const verifierPath = resolve(projectRoot, 'contracts', 'src', 'verifiers', 'EmtunPolicyVerifier.sol');
const jsonFixturePath = resolve(projectRoot, 'scripts', 'fixtures', 'merkle-inclusion-proof.json');
const solidityFixturePath = resolve(projectRoot, 'contracts', 'test', 'fixtures', 'MerkleInclusionFixture.sol');

const policyLeaves: LeafPreimage[] = [
  { action_type: 7n, scope: 42n, expiry: 1_725_312_000n, agent_salt: 998_877_665_544_332_211n },
  { action_type: 11n, scope: 512n, expiry: 1_825_398_400n, agent_salt: 1_234_567_890_123_456_789n },
  { action_type: 255n, scope: 65_537n, expiry: 4_102_444_800n, agent_salt: 340_282_366_920_938_463_463_374_607_431_768_211_283n },
  { action_type: 3n, scope: 9_999n, expiry: 1_901_234_567n, agent_salt: 7_777_777_777_777_777n },
  { action_type: 91n, scope: 1_024n, expiry: 2_222_222_222n, agent_salt: 888_999_000_111_222_333n },
];

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

function normalizeFieldHex(value: string): string {
  const parsed = value.startsWith('0x') ? BigInt(value) : BigInt(value);
  return fieldHexFromBigInt(parsed);
}

function renderSolidityFixture(proofHex: string, publicInputs: string[]): string {
  return `// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library MerkleInclusionFixture {
    function proof() internal pure returns (bytes memory) {
        return hex"${proofHex.slice(2)}";
    }

    function publicInputs() internal pure returns (bytes32[] memory inputs) {
        inputs = new bytes32[](${publicInputs.length});
${publicInputs.map((input, index) => `        inputs[${index}] = bytes32(${input});`).join('\n')}
    }
}
`;
}

async function main(): Promise<void> {
  const compiledCircuit = loadCompiledCircuit(artifactPath);
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
      agent_salt: targetLeaf.agent_salt.toString(),
      path: path.map((value) => value.toString()),
      indices,
    });

    const backend = new UltraHonkBackend(compiledCircuit.bytecode, bb);
    const proof = await backend.generateProof(witness, { verifierTarget: VERIFIER_TARGET });
    const verified = await backend.verifyProof(proof, { verifierTarget: VERIFIER_TARGET });

    if (!verified) {
      throw new Error('EVM-target proof failed local verification.');
    }

    const verificationKey = await backend.getVerificationKey({ verifierTarget: VERIFIER_TARGET });
    const verifier = await backend.getSolidityVerifier(verificationKey, { verifierTarget: VERIFIER_TARGET });
    const publicInputs = proof.publicInputs.map(normalizeFieldHex);
    const expectedPublicInputs = [fieldHexFromBigInt(policyRoot), fieldHexFromBigInt(actionHash)];

    if (publicInputs[0] !== expectedPublicInputs[0] || publicInputs[1] !== expectedPublicInputs[1]) {
      throw new Error(`Unexpected public input ordering: ${publicInputs.join(', ')}`);
    }

    const proofHex = bytesToHex(proof.proof);
    const fixture = {
      verifierTarget: VERIFIER_TARGET,
      policyRoot: policyRoot.toString(),
      actionHash: actionHash.toString(),
      publicInputs,
      proof: proofHex,
      proofBytes: proof.proof.length,
    };

    mkdirSync(dirname(verifierPath), { recursive: true });
    mkdirSync(dirname(jsonFixturePath), { recursive: true });
    mkdirSync(dirname(solidityFixturePath), { recursive: true });

    writeFileSync(verifierPath, verifier);
    writeFileSync(jsonFixturePath, `${JSON.stringify(fixture, null, 2)}\n`);
    writeFileSync(solidityFixturePath, renderSolidityFixture(proofHex, publicInputs));

    console.log(`policy_root: ${policyRoot.toString()}`);
    console.log(`action_hash: ${actionHash.toString()}`);
    console.log(`proof_bytes: ${proof.proof.length}`);
    console.log(`public_inputs: ${publicInputs.length}`);
    console.log('EVM VERIFIER FIXTURE GENERATED');
  } finally {
    await bb.destroy();
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
