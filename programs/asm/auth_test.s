# --- Step 1: Try to write a key WITHOUT auth (should be blocked) ---
li      x10, 0x11111111         # data we want to leak into vault
li      x11, 0                  # vault index 0
ldk     x10, x11                

# Read it back via addk to check (should be 0 + a = a, since vault[0] is still 0)
li      x12, 0x00000000
addk    x13, x12, x11           # x13 = 0 + vault[0]; if blocked, vault[0]=0, so x13=0
                                # if NOT blocked, vault[0]=0x11111111, so x13=0x11111111

# --- Step 2: Try wrong password (should leave auth_bit = 0) ---
li      x1, 0xCAFEBABE          # WRONG password
auth    x1                      # should NOT authenticate

li      x10, 0x22222222
ldk     x10, x11                # ATTEMPT 2: write with bad auth blocked

li      x12, 0x00000000
addk    x14, x12, x11          

# --- Step 3: Correct password unlocks ---
li      x1, 0xDEADBEEF          # correct password
auth    x1                      # auth_bit becomes 1

li      x10, 0x33333333
ldk     x10, x11               

li      x12, 0x00000000
addk    x15, x12, x11           # x15 = 0 + vault[0]; 0x33333333

end:
    j   end