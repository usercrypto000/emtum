import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

type VerifierCallFixture = {
  schema: string;
  generatedFrom: string;
  verifierTarget: string;
  fieldOrder: string[];
  policyRoot: string;
  actionHash: string;
  publicInputs: string[];
  proofBytes: number;
  proof: string;
  metadata: {
    policyRootDecimal: string;
    actionHashDecimal: string;
    proofByteLength: number;
    proofSha256: string;
    publicInputCount: number;
    publicInputMapping: {
      policyRoot: number;
      actionHash: number;
    };
    abiFree: boolean;
  };
};

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const scriptsRoot = resolve(__dirname, '..');
const verifierCallPath = resolve(scriptsRoot, 'fixtures', 'verifier-call.json');

function assertRecord(value: unknown, label: string): asserts value is Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error(`${label} must be a JSON object.`);
  }
}

function assertHex(value: string, label: string): void {
  if (!/^0x[0-9a-f]+$/.test(value)) {
    throw new Error(`${label} must be lowercase 0x-prefixed hex.`);
  }
}

function assertBytes32(value: string, label: string): void {
  assertHex(value, label);

  if (value.length !== 66) {
    throw new Error(`${label} must be exactly 32 bytes.`);
  }
}

function proofByteLength(proof: string): number {
  assertHex(proof, 'proof');

  if (proof.length % 2 !== 0) {
    throw new Error('proof hex length must be even.');
  }

  return (proof.length - 2) / 2;
}

function sha256Hex(hex: string): string {
  return `0x${createHash('sha256').update(Buffer.from(hex.slice(2), 'hex')).digest('hex')}`;
}

function decimalToBytes32(value: string, label: string): string {
  if (!/^[0-9]+$/.test(value)) {
    throw new Error(`${label} must be a decimal string.`);
  }

  const parsed = BigInt(value);
  const hex = parsed.toString(16);

  if (hex.length > 64) {
    throw new Error(`${label} exceeds bytes32 width.`);
  }

  return `0x${hex.padStart(64, '0')}`;
}

function readFixture(path: string): VerifierCallFixture {
  const parsed: unknown = JSON.parse(readFileSync(path, 'utf8'));
  assertRecord(parsed, 'verifier-call fixture');

  return parsed as VerifierCallFixture;
}

function assertArrayEquals(actual: string[], expected: string[], label: string): void {
  if (actual.length !== expected.length || actual.some((value, index) => value !== expected[index])) {
    throw new Error(`${label} mismatch.`);
  }
}

const fixture = readFixture(verifierCallPath);

if (fixture.schema !== 'emtun.verifier-call.v1') {
  throw new Error('Unexpected verifier-call schema.');
}

if (fixture.generatedFrom !== 'scripts/fixtures/merkle-inclusion-proof.json') {
  throw new Error('Unexpected source fixture path.');
}

if (fixture.verifierTarget !== 'evm') {
  throw new Error('Verifier target must be evm.');
}

assertArrayEquals(fixture.fieldOrder, ['policyRoot', 'actionHash'], 'fieldOrder');
assertBytes32(fixture.policyRoot, 'policyRoot');
assertBytes32(fixture.actionHash, 'actionHash');

if (!Array.isArray(fixture.publicInputs) || fixture.publicInputs.length !== 2) {
  throw new Error('publicInputs must contain exactly policyRoot and actionHash.');
}

fixture.publicInputs.forEach((input, index) => assertBytes32(input, `publicInputs[${index}]`));

if (fixture.publicInputs[0] !== fixture.policyRoot) {
  throw new Error('publicInputs[0] must match policyRoot.');
}

if (fixture.publicInputs[1] !== fixture.actionHash) {
  throw new Error('publicInputs[1] must match actionHash.');
}

if (decimalToBytes32(fixture.metadata.policyRootDecimal, 'policyRootDecimal') !== fixture.policyRoot) {
  throw new Error('policyRootDecimal does not encode policyRoot.');
}

if (decimalToBytes32(fixture.metadata.actionHashDecimal, 'actionHashDecimal') !== fixture.actionHash) {
  throw new Error('actionHashDecimal does not encode actionHash.');
}

const byteLength = proofByteLength(fixture.proof);

if (byteLength !== fixture.proofBytes || byteLength !== fixture.metadata.proofByteLength) {
  throw new Error('proof byte length metadata mismatch.');
}

if (sha256Hex(fixture.proof) !== fixture.metadata.proofSha256) {
  throw new Error('proofSha256 metadata mismatch.');
}

if (fixture.metadata.publicInputCount !== 2) {
  throw new Error('publicInputCount must be 2.');
}

if (fixture.metadata.publicInputMapping.policyRoot !== 0 || fixture.metadata.publicInputMapping.actionHash !== 1) {
  throw new Error('public input mapping must keep policyRoot at 0 and actionHash at 1.');
}

if (fixture.metadata.abiFree !== true) {
  throw new Error('verifier-call fixture must remain ABI-free.');
}

console.log(`fixture_schema: ${fixture.schema}`);
console.log(`policy_root: ${fixture.policyRoot}`);
console.log(`action_hash: ${fixture.actionHash}`);
console.log(`proof_bytes: ${fixture.proofBytes}`);
console.log(`proof_sha256: ${fixture.metadata.proofSha256}`);
console.log('SAP FIXTURE AUDIT CONFIRMED');
