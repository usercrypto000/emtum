mod merkle;

use crate::merkle::compute_merkle_root;

fn leaf_hash(action_type: Field, scope: Field, expiry: Field, agent_salt: Field) -> Field {
    let iv = 4 * 18446744073709551616;

    let mut state = [0, 0, 0, iv];
    state[0] += action_type;
    state[1] += scope;
    state[2] += expiry;
    state = std::hash::poseidon2_permutation(state, 4);
    state[0] += agent_salt;
    state = std::hash::poseidon2_permutation(state, 4);
    state[0]
}

fn main(
    policy_root: pub Field,
    action_hash: pub Field,
    action_type: Field,
    scope: Field,
    expiry: Field,
    agent_salt: Field,
    path: [Field; 8],
    indices: [u1; 8],
) {
    let computed_action_hash = leaf_hash(action_type, scope, expiry, agent_salt);
    assert(action_hash == computed_action_hash);

    let computed_root = compute_merkle_root(action_hash, path, indices);
    assert(policy_root == computed_root);
}

#[test]
fn test_leaf_hash_changes_with_expiry() {
    let first = leaf_hash(7, 42, 1000, 555);
    let second = leaf_hash(7, 42, 1001, 555);
    assert(first != second);
}

#[test]
fn test_inclusion_constraints_hold_for_depth_8_tree() {
    let leaf = leaf_hash(7, 42, 1_725_312_000, 998_877);
    let sibling = leaf_hash(8, 99, 1_725_400_000, 123_456);

    let level_one = {
        let iv = 2 * 18446744073709551616;
        let mut state = [0, 0, 0, iv];
        state[0] += leaf;
        state[1] += sibling;
        state = std::hash::poseidon2_permutation(state, 4);
        state[0]
    };

    let zero_hash = {
        let iv = 2 * 18446744073709551616;
        let mut state = [0, 0, 0, iv];
        state = std::hash::poseidon2_permutation(state, 4);
        state[0]
    };

    let path = [sibling, zero_hash, zero_hash, zero_hash, zero_hash, zero_hash, zero_hash, zero_hash];
    let indices = [0, 0, 0, 0, 0, 0, 0, 0];

    let computed_root = compute_merkle_root(leaf, path, indices);
    assert(computed_root != level_one);
}
