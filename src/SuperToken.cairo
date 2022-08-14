%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import (Uint256)
from src.ISuperToken import ISuperToken

@external
func supertoken_mint{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr,
}(contract_address: felt, recipient: felt, amount: Uint256):
    ISuperToken.mint(
        contract_address=contract_address,
        recipient=recipient,
        amount=amount
    )
    return()
end

@external
func supertoken_burn{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr,
}(contract_address: felt, account: felt, amount: Uint256):
    ISuperToken.burn(
        contract_address=contract_address,
        account=account,
        amount=amount
    )
    return()
end