# === XOR encryption (self-inverse) ===
# Authenticate, load key, then XOR every word of memory[0x1000..0x1000+SIZE]
# with vault[0]. End address is set to 0x108EC (covers up to ~63KB image).

# Authenticate (password = 0xDEADBEEF)
li      x1, 0xDEADBEEF
auth    x1

# Load key 0xA5A5A5A5 into vault[0]
li      x2, 0xA5A5A5A5
li      x3, 0
ldk     x2, x3

# Loop pointers
li      x10, 0x1000          # current pointer
li      x11, 0x108EC         # end pointer (0x1000 + 0xF8EC = covers 63KB)

loop:
    lw      x4, 0(x10)
    xork    x5, x4, x3
    sw      x5, 0(x10)
    addi    x10, x10, 4
    blt     x10, x11, loop

end:
    j       end