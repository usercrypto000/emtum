import { readFileSync } from 'node:fs';

import { fieldToString, type Barretenberg } from '@aztec/bb.js';
import type { CompiledCircuit } from '@noir-lang/types';

export type LeafPreimage = {
  action_type: bigint;
  scope: bigint;
  expiry: bigint;
  agent_salt: bigint;
};

export function loadCompiledCircuit(artifactPath: string): CompiledCircuit {
  return JSON.parse(readFileSync(artifactPath, 'utf8')) as CompiledCircuit;
}

export function toFieldBytes(value: bigint): Uint8Array {
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

export function bytesToHex(value: Uint8Array): string {
  return `0x${Array.from(value, (byte) => byte.toString(16).padStart(2, '0')).join('')}`;
}

export function fieldHexFromBigInt(value: bigint): string {
  return `0x${value.toString(16).padStart(64, '0')}`;
}

export async function hashFields(bb: Barretenberg, fields: bigint[]): Promise<bigint> {
  const result = await bb.poseidon2Hash({ inputs: fields.map(toFieldBytes) });
  return BigInt(fieldToString(result.hash));
}

export async function hashLeaf(bb: Barretenberg, leaf: LeafPreimage): Promise<bigint> {
  return hashFields(bb, [leaf.action_type, leaf.scope, leaf.expiry, leaf.agent_salt]);
}

export async function hashPair(bb: Barretenberg, left: bigint, right: bigint): Promise<bigint> {
  return hashFields(bb, [left, right]);
}

export async function computeMerkleRootFromPath(
  bb: Barretenberg,
  leaf: bigint,
  path: bigint[],
  indices: number[],
): Promise<bigint> {
  let current = leaf;

  for (let i = 0; i < path.length; i += 1) {
    current = indices[i] === 1 ? await hashPair(bb, path[i], current) : await hashPair(bb, current, path[i]);
  }

  return current;
}
