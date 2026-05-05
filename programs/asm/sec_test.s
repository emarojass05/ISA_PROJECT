li      x5, 0xDEADBEEF      # password constant
auth    x5                  # set auth_bit = 1

li      x5, 0x12345678      # word to write into vault
li      x6, 0               # vault index 0
ldk     x5, x6              # vault[0] = 0x12345678

li      x7, 0xAA55AA55      # plaintext value
addk    x8, x7, x6          # x8 = x7 + vault[0]
xork    x9, x7, x6          # x9 = x7 XOR vault[0]
tea     x10, x7, x6         # x10 = TEA round on x7 using vault[0]