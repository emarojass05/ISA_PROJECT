luhw    x1, 0x0001
llhw    x1, 0x00FF
addi    x2, x0, 5
addi    x3, x2, -1
add     x4, x2, x3
sw      x4, 8(x0)
lw      x5, 8(x0)
j       -4