luhw    x1, 0x1234
llhw    x1, 0xABCD

addi    x2, x0, 20
xori    x3, x2, 0x00F
slli    x4, x3, 2
srli    x5, x4, 1

add     x6, x2, x3
sub     x7, x6, x5
mul     x8, x2, x3
div     x9, x8, x2
rem     x10, x8, x2

and     x11, x3, x4
or      x12, x3, x4
xor     x13, x3, x4
sll     x14, x3, x2
srl     x15, x4, x2

sw      x15, 0(x0)
lw      x16, 0(x0)