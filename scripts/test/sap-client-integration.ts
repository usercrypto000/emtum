import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Barretenberg, UltraHonkBackend } from '@aztec/bb.js';
import { Noir } from '@noir-lang/noir_js';
import { SAPClient, type ActionParams } from '../src/sap-client.js';
import { fieldHexFromBigInt, loadCompiledCircuit } from './_shared.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = resolve(__dirname, '..', '..');
const artifactPath = resolve(projectRoot, 'circuit', 'target', 'circuit.json');

async function main(): Promise<void> {
  console.log('=== SAPClient Integration Test ===');

  const compiledCircuit = loadCompiledCircuit(artifactPath);
  const noir = new Noir(compiledCircuit);
  const bb = await Barretenberg.new();

  try {
    const client = new SAPClient(bb);

    const action1: ActionParams = {
      actionType: 7n,
      rawCalldata: '0xa9059cbb0000000000000000000000001234567890123456789012345678901234567890',
      expiry: 1_725_312_000n,
      value: 1_000_000_000_000_000_000n, // 1 ETH
      masterAgentSalt: 998_877_665_544n,
    };

    const action2: ActionParams = {
      actionType: 11n,
      rawCalldata: '0x095ea7b30000000000000000000000009999999999999999999999999999999999999999',
      expiry: 1_825_398_400n,
      value: 500_000_000n,
      masterAgentSalt: 123_456_789n,
    };

    const leaf1 = await client.createLeafPreimage(action1);
    const leaf2 = await client.createLeafPreimage(action2);

    const { root, levels, leafHashes } = await client.buildMerkleTree([leaf1, leaf2], 8);
    console.log(`Policy Root: ${root.toString()}`);
    console.log(`Action 1 Hash: ${leafHashes[0].toString()}`);

    const targetIndex = 0;
    const { path, indices } = client.getMerkleProof(levels, targetIndex, 8);

    const { witness } = await noir.execute({
      policy_root: root.toString(),
      action_hash: leafHashes[0].toString(),
      action_type: leaf1.action_type.toString(),
      scope: leaf1.scope.toString(),
      expiry: leaf1.expiry.toString(),
      val_low: leaf1.val_low.toString(),
      val_high: leaf1.val_high.toString(),
      leaf_salt: leaf1.leaf_salt.toString(),
      path: path.map((val) => val.toString()),
      indices,
    });

    const backend = new UltraHonkBackend(compiledCircuit.bytecode, bb);
    const proof = await backend.generateProof(witness, { verifierTarget: 'noir-recursive' });
    const verified = await backend.verifyProof(proof, { verifierTarget: 'noir-recursive' });

    if (!verified) {
      throw new Error('SAPClient proof verification failed.');
    }

    console.log('SAPClient ZK Proof Verified: true');
    console.log('=== SAPClient Integration Test PASSED ===');
  } finally {
    await bb.destroy();
  }
}

main().catch((err: unknown) => {
  console.error(err);
  process.exit(1);
});
