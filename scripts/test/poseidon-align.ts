import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { Barretenberg, UltraHonkBackend } from '@aztec/bb.js';
import { Noir } from '@noir-lang/noir_js';
import { computeMerkleRootFromPath, fieldHexFromBigInt, hashLeaf, hashFields, splitValue, loadCompiledCircuit, type LeafPreimage } from './_shared.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = resolve(__dirname, '..', '..');
const artifactPath = resolve(projectRoot, 'circuit', 'target', 'circuit.json');
const alignmentPath = [101n, 202n, 303n, 404n, 505n, 606n, 707n, 808n];
const alignmentIndices = [0, 1, 0, 1, 1, 0, 1, 0];

type V2Case = {
  name: string;
  action_type: bigint;
  scope: bigint;
  expiry: bigint;
  value: bigint;
  master_agent_salt: bigint;
};

const v2Cases: V2Case[] = [
  {
    name: 'leaf-1',
    action_type: 7n,
    scope: 42n,
    expiry: 1_725_312_000n,
    value: 100n,
    master_agent_salt: 998_877n,
  },
  {
    name: 'leaf-2',
    action_type: 7n,
    scope: 42n,
    expiry: 1_725_398_400n,
    value: 500n,
    master_agent_salt: 123_456n,
  },
  {
    name: 'leaf-3',
    action_type: 255n,
    scope: 65_537n,
    expiry: 4_102_444_800n,
    value: 999_999_999n,
    master_agent_salt: 340_282_366_920_938_463_463_374_607_431_768_211_283n,
  },
];

async function main(): Promise<void> {
  const compiledCircuit = loadCompiledCircuit(artifactPath);
  const noir = new Noir(compiledCircuit);
  const bb = await Barretenberg.new();

  try {
    const backend = new UltraHonkBackend(compiledCircuit.bytecode, bb);

    for (const v2case of v2Cases) {
      const { val_low, val_high } = splitValue(v2case.value);
      const leaf_salt = await hashFields(bb, [v2case.master_agent_salt, v2case.action_type, v2case.expiry]);

      const leaf: LeafPreimage = {
        action_type: v2case.action_type,
        scope: v2case.scope,
        expiry: v2case.expiry,
        val_low,
        val_high,
        leaf_salt,
      };

      const inputs = {
        action_type: leaf.action_type.toString(),
        scope: leaf.scope.toString(),
        expiry: leaf.expiry.toString(),
        val_low: leaf.val_low.toString(),
        val_high: leaf.val_high.toString(),
        leaf_salt: leaf.leaf_salt.toString(),
      };

      const actionHash = await hashLeaf(bb, leaf);
      const policyRoot = await computeMerkleRootFromPath(bb, actionHash, alignmentPath, alignmentIndices);
      const tsHashDecimal = actionHash.toString(10);
      const tsHashHex = fieldHexFromBigInt(actionHash);
      const tsRootHex = fieldHexFromBigInt(policyRoot);

      console.log(`${v2case.name} TS Poseidon hash: ${tsHashDecimal}`);

      const { witness } = await noir.execute({
        policy_root: policyRoot.toString(),
        action_hash: actionHash.toString(),
        ...inputs,
        path: alignmentPath.map((value) => value.toString()),
        indices: alignmentIndices,
      });

      const proof = await backend.generateProof(witness, { verifierTarget: 'noir-recursive' });
      const verified = await backend.verifyProof(proof, { verifierTarget: 'noir-recursive' });
      const noirPolicyRoot = proof.publicInputs[0];
      const noirActionHash = proof.publicInputs[1];

      const matchesActionHash = noirActionHash.toLowerCase() === tsHashHex.toLowerCase();
      const matchesPolicyRoot = noirPolicyRoot.toLowerCase() === tsRootHex.toLowerCase();

      if (!verified || !matchesActionHash || !matchesPolicyRoot) {
        console.error(`${v2case.name} alignment failed.`);
        console.error(`  TypeScript hash (decimal): ${tsHashDecimal}`);
        console.error(`  TypeScript hash (hex): ${tsHashHex}`);
        console.error(`  TypeScript policy root: ${policyRoot.toString()}`);
        console.error(`  TypeScript policy root (hex): ${tsRootHex}`);
        console.error(`  Noir public policy_root: ${noirPolicyRoot}`);
        console.error(`  Noir public action_hash: ${noirActionHash}`);
        console.error(`  Proof verified: ${verified}`);
        process.exit(1);
      }

      console.log(`${v2case.name} policy root: ${policyRoot.toString()}`);
      console.log(`${v2case.name} Noir action hash: ${BigInt(noirActionHash).toString(10)}`);
      console.log(`${v2case.name} proof verified: true`);
    }

    console.log('POSEIDON ALIGNMENT CONFIRMED');
  } finally {
    await bb.destroy();
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
