# length of input feature map (including padding)
nij_len = 6
# length of output feature map
onij_len = 4

# padding applied to input feature map
padding = (nij_len - onij_len) // 2

# kernel size & kij directions
kernel_size = 3
dist = kernel_size // 2

directions = []
for r_offset in range(-dist, dist + 1):
    for c_offset in range(-dist, dist + 1):
        directions.append((r_offset, c_offset))

# base address for second PMEM region
base = nij_len * nij_len * len(directions)  # 36 * 9 = 324

# open new file for second half
file = open('acc_scan2.txt', 'w')

for r in range(padding, nij_len - padding):
    for c in range(padding, nij_len - padding):
        for (r_offset, c_offset) in directions:
            partial_psum_nij = (r + r_offset) * nij_len + (c + c_offset)
            kij = directions.index((r_offset, c_offset))
            A_pmem_addr = base + kij * (nij_len * nij_len) + partial_psum_nij
            file.write('{0:011b}\n'.format(A_pmem_addr))

file.close()
