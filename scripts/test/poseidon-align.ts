import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { Barretenberg, UltraHonkBackend } from '@aztec/bb.js';
import { Noir } from '@noir-lang/noir_js';
import { computeMerkleRootFromPath, fieldHexFromBigInt, hashLeaf, loadCompiledCircuit, type LeafPreimage } from './_shared.js';

type LeafCase = LeafPreimage & {
  name: string;
};

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = resolve(__dirname, '..', '..');
const artifactPath = resolve(projectRoot, 'circuit', 'target', 'circuit.json');
const alignmentPath = [101n, 202n, 303n, 404n, 505n, 606n, 707n, 808n];
const alignmentIndices = [0, 1, 0, 1, 1, 0, 1, 0];

const leafCases: LeafCase[] = [
  {
    name: 'leaf-1',
    action_type: 7n,
    scope: 42n,
    expiry: 1_725_312_000n,
    agent_salt: 998_877_665_544_332_211n,
  },
  {
    name: 'leaf-2',
    action_type: 7n,
    scope: 42n,
    expiry: 1_725_398_400n,
    agent_salt: 998_877_665_544_332_211n,
  },
  {
    name: 'leaf-3',
    action_type: 255n,
    scope: 65_537n,
    expiry: 4_102_444_800n,
    agent_salt: 340_282_366_920_938_463_463_374_607_431_768_211_283n,
  },
];

async function main(): Promise<void> {
  const compiledCircuit = loadCompiledCircuit(artifactPath);
  const noir = new Noir(compiledCircuit);
  const bb = await Barretenberg.new();

  try {
    const backend = new UltraHonkBackend(compiledCircuit.bytecode, bb);

    for (const leaf of leafCases) {
      const inputs = {
        action_type: leaf.action_type.toString(),
        scope: leaf.scope.toString(),
        expiry: leaf.expiry.toString(),
        agent_salt: leaf.agent_salt.toString(),
      };
      const actionHash = await hashLeaf(bb, leaf);
      const policyRoot = await computeMerkleRootFromPath(bb, actionHash, alignmentPath, alignmentIndices);
      const tsHashDecimal = actionHash.toString(10);
      const tsHashHex = fieldHexFromBigInt(actionHash);
      const tsRootHex = fieldHexFromBigInt(policyRoot);

      console.log(`${leaf.name} TS Poseidon hash: ${tsHashDecimal}`);

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
        console.error(`${leaf.name} alignment failed.`);
        console.error(`  TypeScript hash (decimal): ${tsHashDecimal}`);
        console.error(`  TypeScript hash (hex): ${tsHashHex}`);
        console.error(`  TypeScript policy root: ${policyRoot.toString()}`);
        console.error(`  TypeScript policy root (hex): ${tsRootHex}`);
        console.error(`  Noir public policy_root: ${noirPolicyRoot}`);
        console.error(`  Noir public action_hash: ${noirActionHash}`);
        console.error(`  Proof verified: ${verified}`);
        process.exit(1);
      }

      console.log(`${leaf.name} policy root: ${policyRoot.toString()}`);
      console.log(`${leaf.name} Noir action hash: ${BigInt(noirActionHash).toString(10)}`);
      console.log(`${leaf.name} proof verified: true`);
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
