import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { Barretenberg, UltraHonkBackend, fieldToString } from '@aztec/bb.js';
import { Noir } from '@noir-lang/noir_js';
import type { CompiledCircuit } from '@noir-lang/types';

type LeafCase = {
  name: string;
  action_type: bigint;
  scope: bigint;
  expiry: bigint;
  agent_salt: bigint;
};

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = resolve(__dirname, '..', '..');
const artifactPath = resolve(projectRoot, 'circuit', 'target', 'circuit.json');

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

function bytesToHex(value: Uint8Array): string {
  return `0x${Array.from(value, (byte) => byte.toString(16).padStart(2, '0')).join('')}`;
}

function normalizeFieldValue(value: unknown): { decimal: string; hex: string } {
  if (typeof value !== 'string' && typeof value !== 'number' && typeof value !== 'boolean') {
    throw new Error(`Unexpected Noir return value shape: ${JSON.stringify(value)}`);
  }

  const bigintValue = BigInt(value);
  return {
    decimal: bigintValue.toString(10),
    hex: `0x${bigintValue.toString(16).padStart(64, '0')}`,
  };
}

async function main(): Promise<void> {
  const compiledCircuit = JSON.parse(readFileSync(artifactPath, 'utf8')) as CompiledCircuit;
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

      const poseidonResult = await bb.poseidon2Hash({
        inputs: [
          toFieldBytes(leaf.action_type),
          toFieldBytes(leaf.scope),
          toFieldBytes(leaf.expiry),
          toFieldBytes(leaf.agent_salt),
        ],
      });

      const tsHashDecimal = fieldToString(poseidonResult.hash);
      const tsHashHex = bytesToHex(poseidonResult.hash);

      console.log(`${leaf.name} TS Poseidon hash: ${tsHashDecimal}`);

      const { witness, returnValue } = await noir.execute(inputs);
      const noirReturnValue = normalizeFieldValue(returnValue);

      const proof = await backend.generateProof(witness, { verifierTarget: 'noir-recursive' });
      const verified = await backend.verifyProof(proof, { verifierTarget: 'noir-recursive' });
      const noirPublicOutput = proof.publicInputs[0];

      const matchesReturnValue =
        noirReturnValue.decimal === tsHashDecimal && noirReturnValue.hex.toLowerCase() === tsHashHex.toLowerCase();
      const matchesPublicOutput = noirPublicOutput.toLowerCase() === tsHashHex.toLowerCase();

      if (!verified || !matchesReturnValue || !matchesPublicOutput) {
        console.error(`${leaf.name} alignment failed.`);
        console.error(`  TypeScript hash (decimal): ${tsHashDecimal}`);
        console.error(`  TypeScript hash (hex): ${tsHashHex}`);
        console.error(`  Noir return value (decimal): ${noirReturnValue.decimal}`);
        console.error(`  Noir return value (hex): ${noirReturnValue.hex}`);
        console.error(`  Noir public output: ${noirPublicOutput}`);
        console.error(`  Proof verified: ${verified}`);
        process.exit(1);
      }

      console.log(`${leaf.name} Noir output: ${noirReturnValue.decimal}`);
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
