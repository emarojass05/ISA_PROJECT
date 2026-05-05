# === TEA Encryption (TEST: 1 round only) ===

li      x1, 0xDEADBEEF
nop
nop
nop
auth    x1
nop
nop

# Store the same key in every vault position 0..15
li      x16, 0xA5A5A5A5
nop
nop
nop
li      x2, 0
li      x3, 16
nop
nop

key_init_loop:
    ldk     x16, x2
    nop
    nop
    addi    x2, x2, 1
    blt     x2, x3, key_init_loop

# DELTA constant
li      x7, 0x9E3779B9
nop
nop

# Memory range (only 64 bytes for tiny.bin)
li      x10, 0x1000
li      x11, 0x1040

loop_blocks:
    lw      x4, 0(x10)
    lw      x5, 4(x10)
    nop
    nop

    li      x6, 0          # sum = 0
    li      x8, 1          # rounds = 1 (debug)
    nop

round_loop:
    add     x6, x6, x7     # sum += DELTA

    add     x9, x5, x6     # x9 = v1 + sum
    nop
    tea     x12, x5, x9
    nop
    nop
    add     x4, x4, x12    # v0 += F(v1, sum, key)

    add     x9, x4, x6     # x9 = v0_new + sum
    nop
    tea     x12, x4, x9
    nop
    nop
    add     x5, x5, x12    # v1 += F(v0_new, sum, key)

    addi    x8, x8, -1
    bne     x8, x0, round_loop

    sw      x4, 0(x10)
    sw      x5, 4(x10)

    addi    x10, x10, 8
    blt     x10, x11, loop_blocks

end:
    j       end