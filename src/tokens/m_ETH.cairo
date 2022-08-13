%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256, uint256_lt, uint256_signed_nn

from openzeppelin.access.ownable.library import Ownable
from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.token.erc20.library import ERC20

from src.interfaces.ISuperToken import ISuperToken

#
# Events
#
@event
func Mint(token_addr : felt, value : Uint256):
end

@event
func Burn(token_addr : felt, value : Uint256):
end

#
# external functions
#

# check if user has sufficient tokens in wallet
func assert_sufficient_tokens{
    syscall_ptr : felt*, 
    pedersen_ptr : HashBuiltin*, 
    range_check_ptr
    }(token_address: felt, amount: Uint256):
    alloc_locals
    # check for non-zero amount
    with_attr error_message("Token amount is less than 0"):
        let (is_token_non_zero) = uint256_signed_nn(amount)
        assert is_token_non_zero = 1
    end
    # check for sufficient tokens
    with_attr error_message("Insufficient Tokens in Wallet"):
        # get caller address and balance
        let (caller_addr) = get_caller_address()
        let (balance) = IERC20.balanceOf(contract_address=token_address, account=caller_addr)
        let (is_token_amount_sufficient) = uint256_lt(amount, balance)
        assert is_token_amount_sufficient = 1
    end
    return ()
end

# function callable by users
@external
func upgrade_by_eth{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    token_address : felt, amount : Uint256
):
    # get caller address and balance
    alloc_locals
    let (caller_addr) = get_caller_address()
    local caller_addr = caller_addr
    # check for sufficient token balance
    assert_sufficient_tokens(token_address, amount)
    # burn underlying token
    # ERC20._burn(amount)
    # mint SuperToken
    # ISuperToken.mint(token_address, amount)
    Mint.emit(token_address, amount)

    return ()
end

# function callable by users
@external
func downgrade_to_eth{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    token_address : felt, amount : Uint256
):
    # check for sufficient token balance in SuperToken contract ?
    # get caller address and balance
    alloc_locals
    let (caller_addr) = get_caller_address()
    local caller_addr = caller_addr
    # burn SuperToken
    # ISuperToken.burn(token_address, amount)
    Burn.emit(token_address, amount)
    # mint underlying token
    # ERC20._mint(caller_addr, amount)
    return ()
end
