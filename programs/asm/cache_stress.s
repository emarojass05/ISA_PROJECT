# Cache L2 hit stress: 4 lines mapping to the same L1 set and same L2 set
# (stride 0x1000 keeps addr[11:0] constant). L1 is 2-way and thrashes; L2 is
# 4-way and retains all four lines, so each L1 miss becomes an L2 hit.
        li      x10, 0          # loop counter
        li      x11, 40         # iterations
loop:
        li      x3, 0x0000
        lw      x4, 0(x3)
        li      x3, 0x1000
        lw      x4, 0(x3)
        li      x3, 0x2000
        lw      x4, 0(x3)
        li      x3, 0x3000
        lw      x4, 0(x3)
        addi    x10, x10, 1
        blt     x10, x11, loop
        nop
        nop
end:
        j       end
