import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Barretenberg, UltraHonkBackend } from '@aztec/bb.js';
import { Noir } from '@noir-lang/noir_js';
import { SAPClient, type ActionParams } from '../src/sap-client.js';
import { fieldHexFromBigInt, loadCompiledCircuit } from '../test/_shared.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = resolve(__dirname, '..', '..');
const artifactPath = resolve(projectRoot, 'circuit', 'target', 'circuit.json');

type RawActionInput = {
  actionType: string;
  rawCalldata: string;
  expiry: string;
  value: string;
  masterAgentSalt: string;
};

async function main() {
  const args = process.argv.slice(2);
  const command = args[0] ?? 'help';

  if (command === 'help') {
    console.log(`
SAP V2 Command Line Tool (sap-cli)

Usage:
  tsx bin/sap-cli.ts build-tree <actions_json_file>
  tsx bin/sap-cli.ts prove-leaf <actions_json_file> <leaf_index>
  tsx bin/sap-cli.ts help
`);
    return;
  }

  const bb = await Barretenberg.new();
  const client = new SAPClient(bb);

  try {
    if (command === 'build-tree') {
      const filePath = resolve(process.cwd(), args[1] ?? 'actions.json');
      const rawData: RawActionInput[] = JSON.parse(readFileSync(filePath, 'utf8'));

      const preimages = await Promise.all(
        rawData.map((item) =>
          client.createLeafPreimage({
            actionType: BigInt(item.actionType),
            rawCalldata: item.rawCalldata,
            expiry: BigInt(item.expiry),
            value: BigInt(item.value),
            masterAgentSalt: BigInt(item.masterAgentSalt),
          })
        )
      );

      const { root, leafHashes } = await client.buildMerkleTree(preimages, 8);

      console.log('=== SAP V2 Policy Tree Summary ===');
      console.log(`Policy Root (Dec): ${root.toString()}`);
      console.log(`Policy Root (Hex): ${fieldHexFromBigInt(root)}`);
      console.log(`Total Leaves: ${leafHashes.length}`);
      leafHashes.forEach((hash, idx) => {
        console.log(`  Leaf [${idx}]: ${fieldHexFromBigInt(hash)}`);
      });
    } else if (command === 'prove-leaf') {
      const filePath = resolve(process.cwd(), args[1] ?? 'actions.json');
      const leafIndex = Number.parseInt(args[2] ?? '0', 10);
      const rawData: RawActionInput[] = JSON.parse(readFileSync(filePath, 'utf8'));

      const preimages = await Promise.all(
        rawData.map((item) =>
          client.createLeafPreimage({
            actionType: BigInt(item.actionType),
            rawCalldata: item.rawCalldata,
            expiry: BigInt(item.expiry),
            value: BigInt(item.value),
            masterAgentSalt: BigInt(item.masterAgentSalt),
          })
        )
      );

      const { root, levels, leafHashes } = await client.buildMerkleTree(preimages, 8);
      const targetLeaf = preimages[leafIndex];
      const targetHash = leafHashes[leafIndex];
      const { path, indices } = client.getMerkleProof(levels, leafIndex, 8);

      const compiledCircuit = loadCompiledCircuit(artifactPath);
      const noir = new Noir(compiledCircuit);

      const { witness } = await noir.execute({
        policy_root: root.toString(),
        action_hash: targetHash.toString(),
        action_type: targetLeaf.action_type.toString(),
        scope: targetLeaf.scope.toString(),
        expiry: targetLeaf.expiry.toString(),
        val_low: targetLeaf.val_low.toString(),
        val_high: targetLeaf.val_high.toString(),
        leaf_salt: targetLeaf.leaf_salt.toString(),
        path: path.map((val) => val.toString()),
        indices,
      });

      const backend = new UltraHonkBackend(compiledCircuit.bytecode, bb);
      const proof = await backend.generateProof(witness, { verifierTarget: 'evm' });
      const verified = await backend.verifyProof(proof, { verifierTarget: 'evm' });

      console.log('=== ZK Proof Generation Output ===');
      console.log(`Policy Root: ${fieldHexFromBigInt(root)}`);
      console.log(`Action Hash: ${fieldHexFromBigInt(targetHash)}`);
      console.log(`Proof Bytes: ${proof.proof.length}`);
      console.log(`Verified (EVM Target): ${verified}`);
    } else {
      console.error(`Unknown command: ${command}`);
      process.exit(1);
    }
  } finally {
    await bb.destroy();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
