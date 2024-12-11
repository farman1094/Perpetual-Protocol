### Side Quest Yul & Memory
This is also from the project

1. In the safeTransferFrom function, what does 0x23b872dd000000000000000000000000 represent and what does it mean when used in the following context on line 192: mstore(0x0c, 0x23b872dd000000000000000000000000).
- This small part here is the signature `0x23b872dd000000000000000000000000` of the funciton `transferFrom(address,address,uint)` which is going to use the function for calling. In context of the line  `mstore(0x0c, 0x23b872dd000000000000000000000000)` It's a command in Yul to add this in memory It just shown `0x23b872dd000000000000000000000000` But actually this word is `0000000000000000000000000000000023b872dd000000000000000000000000` because as the data pushed to memory it's done in 32 bytes so here this is the whole word command mentioning. It also mentioned to start storing from `0x0c` (12 bytes in dec) so this long word as initial padding of 16 bytes and 4 data signature. So this word becomes `0000000000000000000000000000000000000000000000000000000023b872dd` like as we want. And In line `mstore(0x2c, shl(96, from))` it storing form 0x2c (44 in dec) saving initial 12 bytes becuase which going to override by this `0x23b872dd000000000000000000000000` signature extra 0's. 

- In call we `call(gas(), token, 0, 0x1c, 0x64, 0x00, 0x20)` we start taking input from 0x1c (28 in dec) this where signature start and data length is 0x64 (100). So the data is managed this way 4 byte sig, 32 byte addr. 32 byte addr, 32 byte uint input.
##

2. In the safeTransferFrom function, why is shl used on line 191 to shift the from to the left by 96 bits?
- So this line is storing address and storing from 0x2c (44 in dec) basically starting storing from 12 bytes as the remaining bytes left is 20 in the word and address is also 20 bytes long. Address is need to be shifted left and we need to store only address nothing else.
```diff
+ 000000000000000000000000760B5669b25764Dcaaee01607d86fCB6Aab1cB33 // instead of storing like this 
- 760B5669b25764Dcaaee01607d86fCB6Aab1cB33000000000000000000000000 // we store this 
```
##
3. In the safeTransferFrom function, is this memory safe assembly? Why or why not?
- Yes this function is memory safe pointer first of all free memory pointer is actually not used we only used memory till 0x80, not further. So free memory pointer not need to be updated. However, there are some memory we used which shouldn't be touched such as the `0x60` which is the blank space and `0x40` which is for the pointer of free space. But that were restored in the end so no issue at all.
##
4. In the safeTransferFrom function, on line 197, why is 0x1c provided as the 4th argument to call?
- `0x1c`(28 in dec) the 4th arg of the call is taking where the data is starting from. And as we stored that in memory like that `0000000000000000000000000000000000000000000000000000000023b872dd` the signature is starting from the end which is 28 byte and the calldata is long as `0x64` mean 100.
4 byte for sig, 32 byte for address, 32 byte for another address and last 32 byte for the amountToTransfer.
## 
5. In the safeTransfer function, on line 266, why is revert used with 0x1c and 0x04.
- So first we storing the sig of TransferFailed Error signature (error signature has created like function), as the function we are reverting with the error. The line is mentioning the signature is starting from `0x1c` (28 in dec) and the sig is `0x04`(4 in dec) byte long
##
6. In the safeTransfer function, on line 268, why is 0 mstore’d at 0x34.
- So initialy we store the amount in `0x34` the amount is 32 byte long so it's override some part (20 byte) of `0x40` which is reserved for free memory poiter. So we have to reset that to 0. We do not have to worry because inittialy the pointer store in 0x40 is actualy store in last byte of that. So only half of them is used which later turned to 0 main part rest half is untouched.
##
7. In the safeApprove function, on line 317, why is mload(0x00) validated for equality to 1?
- Because during external call `call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)` we saved the return data at position `0x00` but we want to make sure it only return `0x0000000000000000000000000000000000000000000000000000000000000001` which is true, not more than data which could cause other issue and to check if call not failed if false it will be all 0;
##
8. In the safeApprove function, if the token returns false from the approve(address,uint256) function, what happens?
- There are checks 
```solidity
if iszero(
        and(
            or(eq(mload(0x00), 1), iszero(returndatasize())), 
            call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
        )
    ) {
        mstore(0x00, 0x3e3f8f73) // `ApproveFailed()`.
        revert(0x1c, 0x04)
    }
    mstore(0x34, 0) 
}
```
first `eq` become 0 as it comparing 0 with 1. Then returndatasize is 32 but as inside `iszero` it also become 0. or(0,0) become top line whole 0. Bottom is also 0 as it returned false. so this become `and(0,0)` which end up 0 as well. Now it all inside `iszero` so it become 1. Now as 1 is true it goes inside if loop. Now `0x3e3f8f73` (`ApproveFailed()`) sig is saved to memory and later reverted with that.

