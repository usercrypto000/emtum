fn hash_pair(left: Field, right: Field) -> Field {
    let iv = 2 * 18446744073709551616;

    let mut state = [0, 0, 0, iv];
    state[0] += left;
    state[1] += right;
    state = std::hash::poseidon2_permutation(state, 4);
    state[0]
}

pub fn compute_merkle_root(leaf: Field, path: [Field; 8], indices: [u1; 8]) -> Field {
    let mut current = leaf;

    for i in 0..8 {
        let is_right = indices[i] != 0;
        current = if is_right {
            hash_pair(path[i], current)
        } else {
            hash_pair(current, path[i])
        };
    }

    current
}
