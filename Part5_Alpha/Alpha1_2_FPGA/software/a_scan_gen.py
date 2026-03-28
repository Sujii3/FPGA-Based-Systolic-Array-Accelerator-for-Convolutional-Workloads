# length of input feature map (including padding)
nij_len = 6
# length of output feature map
onij_len = 4

# padding applied to input feature map calculated
padding = int((nij_len - onij_len) / 2)

# calculate all distances / kij mappings given the kernel size
kernel_size = 3
dist = 3 // 2

# these directions are created in the same order as the kij enumeration
directions = []
for r_offset in range(-1 * dist, dist + 1):
    for c_offset in range(-1 * dist, dist + 1):
        directions.append((r_offset, c_offset))



file = open('acc_scan.txt', 'w')

for r in range(padding, nij_len - padding):
    for c in range(padding, nij_len - padding):
        # calculating output for the current r, c

        for (r_offset, c_offset) in directions:
            partial_psum_nij = (r + r_offset) * nij_len + (c + c_offset)
            kij = directions.index((r_offset, c_offset))

            # calculate the address in A_pmem using these values
            # A_pmem is primarly indexed by kij, over all input nij
            file.write('{0:011b}\n'.format(
                kij * (nij_len * nij_len) + \
                partial_psum_nij
            ))