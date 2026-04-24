luhw    x5, 0x1234
llhw    x5, 0xABCD
addi    x6, x0, 10
add     x7, x5, x6
sw      x7, 0(x0)
lw      x8, 0(x0)
j       0