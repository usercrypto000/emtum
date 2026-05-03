import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

type MerkleInclusionProofFixture = {
  verifierTarget: string;
  policyRoot: string;
  actionHash: string;
  publicInputs: string[];
  proof: string;
  proofBytes: number;
};

type VerifierCallFixture = {
  schema: 'emtun.verifier-call.v1';
  generatedFrom: string;
  verifierTarget: string;
  fieldOrder: ['policyRoot', 'actionHash'];
  callStyles: {
    verifyAuthorization: {
      description: string;
      arguments: ['proof', 'policyRoot', 'actionHash'];
    };
    isAuthorized: {
      description: string;
      arguments: ['agentId', 'proof', 'actionHash'];
    };
    isTaskAuthorized: {
      description: string;
      arguments: ['agentId', 'proof', 'actionHash'];
    };
  };
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
      policyRoot: 0;
      actionHash: 1;
    };
    abiFree: true;
  };
};

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const scriptsRoot = resolve(__dirname, '..');
const sourceFixturePath = resolve(scriptsRoot, 'fixtures', 'merkle-inclusion-proof.json');
const outputFixturePath = resolve(scriptsRoot, 'fixtures', 'verifier-call.json');
const sourceFixtureLabel = 'scripts/fixtures/merkle-inclusion-proof.json';

function assertRecord(value: unknown, label: string): asserts value is Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error(`${label} must be a JSON object.`);
  }
}

function readMerkleFixture(path: string): MerkleInclusionProofFixture {
  const parsed: unknown = JSON.parse(readFileSync(path, 'utf8'));
  assertRecord(parsed, 'Merkle inclusion proof fixture');

  const { verifierTarget, policyRoot, actionHash, publicInputs, proof, proofBytes } = parsed;

  if (typeof verifierTarget !== 'string') {
    throw new Error('verifierTarget must be a string.');
  }

  if (typeof policyRoot !== 'string') {
    throw new Error('policyRoot must be a decimal string.');
  }

  if (typeof actionHash !== 'string') {
    throw new Error('actionHash must be a decimal string.');
  }

  if (!Array.isArray(publicInputs) || !publicInputs.every((input) => typeof input === 'string')) {
    throw new Error('publicInputs must be an array of hex strings.');
  }

  if (typeof proof !== 'string') {
    throw new Error('proof must be a hex string.');
  }

  if (typeof proofBytes !== 'number' || !Number.isInteger(proofBytes) || proofBytes < 0) {
    throw new Error('proofBytes must be a non-negative integer.');
  }

  return { verifierTarget, policyRoot, actionHash, publicInputs, proof, proofBytes };
}

function isHex(value: string): boolean {
  return /^0x[0-9a-fA-F]*$/.test(value);
}

function normalizeBytes32FromDecimal(value: string, label: string): string {
  const parsed = BigInt(value);

  if (parsed < 0n) {
    throw new Error(`${label} must be non-negative.`);
  }

  const hex = parsed.toString(16);

  if (hex.length > 64) {
    throw new Error(`${label} exceeds bytes32 width.`);
  }

  return `0x${hex.padStart(64, '0')}`;
}

function normalizeBytes32Hex(value: string, label: string): string {
  if (!isHex(value)) {
    throw new Error(`${label} must be 0x-prefixed hex.`);
  }

  const body = value.slice(2);

  if (body.length > 64) {
    throw new Error(`${label} exceeds bytes32 width.`);
  }

  return `0x${body.padStart(64, '0').toLowerCase()}`;
}

function normalizeProofHex(value: string): string {
  if (!isHex(value)) {
    throw new Error('proof must be 0x-prefixed hex.');
  }

  const body = value.slice(2);

  if (body.length % 2 !== 0) {
    throw new Error('proof hex length must be even.');
  }

  return `0x${body.toLowerCase()}`;
}

function byteLength(hex: string): number {
  return (hex.length - 2) / 2;
}

function sha256Hex(hex: string): string {
  return `0x${createHash('sha256').update(Buffer.from(hex.slice(2), 'hex')).digest('hex')}`;
}

function buildVerifierCallFixture(source: MerkleInclusionProofFixture): VerifierCallFixture {
  const policyRoot = normalizeBytes32FromDecimal(source.policyRoot, 'policyRoot');
  const actionHash = normalizeBytes32FromDecimal(source.actionHash, 'actionHash');
  const publicInputs = source.publicInputs.map((input, index) => normalizeBytes32Hex(input, `publicInputs[${index}]`));
  const proof = normalizeProofHex(source.proof);
  const proofByteLength = byteLength(proof);

  if (publicInputs.length < 2) {
    throw new Error('publicInputs must contain policyRoot and actionHash.');
  }

  if (publicInputs[0] !== policyRoot) {
    throw new Error('publicInputs[0] must match policyRoot.');
  }

  if (publicInputs[1] !== actionHash) {
    throw new Error('publicInputs[1] must match actionHash.');
  }

  if (proofByteLength !== source.proofBytes) {
    throw new Error(`proofBytes mismatch: fixture declares ${source.proofBytes}, proof hex encodes ${proofByteLength}.`);
  }

  return {
    schema: 'emtun.verifier-call.v1',
    generatedFrom: sourceFixtureLabel,
    verifierTarget: source.verifierTarget,
    fieldOrder: ['policyRoot', 'actionHash'],
    callStyles: {
      verifyAuthorization: {
        description: 'EmtunVerifierAdapter call shape using proof bytes and the two explicit SAP public inputs.',
        arguments: ['proof', 'policyRoot', 'actionHash'],
      },
      isAuthorized: {
        description: 'EmtunAuthorizationReader call shape where the policy root is resolved from the current chain head.',
        arguments: ['agentId', 'proof', 'actionHash'],
      },
      isTaskAuthorized: {
        description: 'TaskAuthorizationGate call shape requiring registration, active identity attestation, and SAP proof validity.',
        arguments: ['agentId', 'proof', 'actionHash'],
      },
    },
    policyRoot,
    actionHash,
    publicInputs,
    proofBytes: source.proofBytes,
    proof,
    metadata: {
      policyRootDecimal: source.policyRoot,
      actionHashDecimal: source.actionHash,
      proofByteLength,
      proofSha256: sha256Hex(proof),
      publicInputCount: publicInputs.length,
      publicInputMapping: {
        policyRoot: 0,
        actionHash: 1,
      },
      abiFree: true,
    },
  };
}

const source = readMerkleFixture(sourceFixturePath);
const verifierCallFixture = buildVerifierCallFixture(source);

writeFileSync(outputFixturePath, `${JSON.stringify(verifierCallFixture, null, 2)}\n`);

console.log(`exported: ${outputFixturePath}`);
console.log(`policy_root: ${verifierCallFixture.policyRoot}`);
console.log(`action_hash: ${verifierCallFixture.actionHash}`);
console.log(`proof_bytes: ${verifierCallFixture.proofBytes}`);
