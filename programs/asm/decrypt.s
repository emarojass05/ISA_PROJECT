# === XOR decryption (same logic as encrypt because XOR is self-inverse) ===
li      x1, 0xDEADBEEF
auth    x1

li      x2, 0xA5A5A5A5
li      x3, 0
ldk     x2, x3

li      x10, 0x1000
li      x11, 0x108EC

loop:
    lw      x4, 0(x10)
    xork    x5, x4, x3
    sw      x5, 0(x10)
    addi    x10, x10, 4
    blt     x10, x11, loop

end:
    j       end