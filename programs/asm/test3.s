start:
nop
li      x5, 0x00010002
mv      x6, x5
addi    x7, x0, 2

loop:
sub     x6, x6, x7
beq     x6, x0, done
bne     x6, x7, skip
bgt     x6, x7, skip
blt     x6, x7, done
bge     x6, x7, skip
ble     x6, x7, done

skip:
call    func
j       loop

func:
addi    x10, x0, 99
ret

done:
jal     x1, end
jr      x1

end:
j       0