import { readFileSync, writeFileSync } from 'node:fs';
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
  metadata: {
    proofSha256: string;
    publicInputCount: number;
    publicInputMapping: {
      policyRoot: number;
      actionHash: number;
    };
    abiFree: boolean;
  };
};

type SapPrimitiveManifest = {
  schema: 'emtun.sap-primitive.v1';
  primitive: 'Scoped Authorization Proof';
  generatedFrom: string[];
  circuit: {
    package: 'circuit';
    compilerVersion: string;
    treeDepth: 8;
    maxLeaves: 256;
    hash: 'Poseidon2';
    leafPreimage: ['action_type', 'scope', 'expiry', 'agent_salt'];
  };
  proofStatement: string[];
  publicInputs: {
    policyRoot: string;
    actionHash: string;
  };
  privateWitness: string[];
  verifierFixture: {
    schema: string;
    target: string;
    proofBytes: number;
    proofSha256: string;
    publicInputCount: number;
    publicInputMapping: {
      policyRoot: number;
      actionHash: number;
    };
    abiFree: boolean;
  };
  contractSurfaces: {
    verifierAdapter: string;
    authorizationReader: string;
    authorizationStatusView: string;
    taskAuthorizationGate: string;
  };
  verificationCommands: {
    scripts: string[];
    circuit: string[];
    contracts: string[];
  };
  nonGoals: string[];
};

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const scriptsRoot = resolve(__dirname, '..');
const repoRoot = resolve(scriptsRoot, '..');
const verifierCallPath = resolve(scriptsRoot, 'fixtures', 'verifier-call.json');
const manifestPath = resolve(scriptsRoot, 'fixtures', 'sap-primitive-manifest.json');
const nargoTomlPath = resolve(repoRoot, 'circuit', 'Nargo.toml');

function assertRecord(value: unknown, label: string): asserts value is Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error(`${label} must be a JSON object.`);
  }
}

function readVerifierCallFixture(path: string): VerifierCallFixture {
  const parsed: unknown = JSON.parse(readFileSync(path, 'utf8'));
  assertRecord(parsed, 'verifier-call fixture');

  return parsed as VerifierCallFixture;
}

function readCompilerVersion(path: string): string {
  const nargoToml = readFileSync(path, 'utf8');
  const match = nargoToml.match(/^compiler_version\s*=\s*"([^"]+)"$/m);

  if (!match) {
    throw new Error('Nargo.toml must pin compiler_version.');
  }

  return match[1];
}

function buildManifest(verifierCall: VerifierCallFixture, compilerVersion: string): SapPrimitiveManifest {
  if (verifierCall.schema !== 'emtun.verifier-call.v1') {
    throw new Error('verifier-call fixture schema mismatch.');
  }

  if (verifierCall.fieldOrder[0] !== 'policyRoot' || verifierCall.fieldOrder[1] !== 'actionHash') {
    throw new Error('verifier-call field order must be policyRoot, actionHash.');
  }

  if (verifierCall.publicInputs[0] !== verifierCall.policyRoot || verifierCall.publicInputs[1] !== verifierCall.actionHash) {
    throw new Error('verifier-call public inputs must map to policyRoot and actionHash.');
  }

  return {
    schema: 'emtun.sap-primitive.v1',
    primitive: 'Scoped Authorization Proof',
    generatedFrom: ['scripts/fixtures/verifier-call.json', 'circuit/Nargo.toml'],
    circuit: {
      package: 'circuit',
      compilerVersion,
      treeDepth: 8,
      maxLeaves: 256,
      hash: 'Poseidon2',
      leafPreimage: ['action_type', 'scope', 'expiry', 'agent_salt'],
    },
    proofStatement: [
      'The private leaf preimage hashes to the public action_hash.',
      'The action_hash is included in the committed policy_root.',
      'Only the current policy root is accepted by the authorization reader.',
    ],
    publicInputs: {
      policyRoot: verifierCall.policyRoot,
      actionHash: verifierCall.actionHash,
    },
    privateWitness: [
      'action_type',
      'scope',
      'expiry',
      'agent_salt',
      'path[8]',
      'indices[8]',
      'all other policy leaves',
    ],
    verifierFixture: {
      schema: verifierCall.schema,
      target: verifierCall.verifierTarget,
      proofBytes: verifierCall.proofBytes,
      proofSha256: verifierCall.metadata.proofSha256,
      publicInputCount: verifierCall.metadata.publicInputCount,
      publicInputMapping: verifierCall.metadata.publicInputMapping,
      abiFree: verifierCall.metadata.abiFree,
    },
    contractSurfaces: {
      verifierAdapter: 'verifyAuthorization(proof, policyRoot, actionHash)',
      authorizationReader: 'isAuthorized(agentId, proof, actionHash)',
      authorizationStatusView: 'getAgentAuthorizationStatus(agentId, proof, actionHash)',
      taskAuthorizationGate: 'isTaskAuthorized(agentId, proof, actionHash)',
    },
    verificationCommands: {
      scripts: ['npm run validate', 'npm run sap-fixture-audit', 'npm run export:sap-manifest'],
      circuit: ['nargo test'],
      contracts: [
        'forge test --match-path test/PrimitiveBoundarySmoke.t.sol -vvv',
        'forge test --match-path test/ReadSurfaceGas.t.sol -vvv',
      ],
    },
    nonGoals: [
      'Execution correctness is not proven.',
      'Requester acceptance is not execution verification.',
      'Historical policy roots are not valid authorization roots.',
    ],
  };
}

const verifierCall = readVerifierCallFixture(verifierCallPath);
const compilerVersion = readCompilerVersion(nargoTomlPath);
const manifest = buildManifest(verifierCall, compilerVersion);

writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

console.log(`exported: ${manifestPath}`);
console.log(`schema: ${manifest.schema}`);
console.log(`policy_root: ${manifest.publicInputs.policyRoot}`);
console.log(`action_hash: ${manifest.publicInputs.actionHash}`);
console.log(`proof_sha256: ${manifest.verifierFixture.proofSha256}`);
console.log('SAP PRIMITIVE MANIFEST EXPORTED');
