%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256, uint256_eq
from openzeppelin.token.erc20.IERC20 import IERC20

from src.m_token import get_owner, get_underlying_token_addr, wrap
from tests.utils.Im_token import Im_token

const OWNER_ADDRESS = 123456

@external
func __setup__():
    tempvar erc20_address
    %{
        context.erc20_address = deploy_contract(
        "./src/ERC20MintableBurnable.cairo",
        [   1111, # name
            1111, # symbol 
            18,   # decimal 
            1000000,0, # initial supply
            ids.OWNER_ADDRESS, # recipient
            ids.OWNER_ADDRESS, # owner
        ]
        ).contract_address
        ids.erc20_address = context.erc20_address

        context.contract_address = deploy_contract(
           "./src/m_token.cairo",
           [
                777,             # name
                777,             # symbol
                # 18,               # owner
                ids.OWNER_ADDRESS, # owner
                ids.erc20_address # underlying token_addr
            ]
           ).contract_address
    %}
    return ()
end

@external
func test_wrap_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    tempvar erc20_address
    tempvar contract_address
    %{
        ids.contract_address = context.contract_address
        ids.erc20_address = context.erc20_address
        stop_prank_callable = start_prank(ids.OWNER_ADDRESS, target_contract_address=ids.contract_address)
        stop_prank_callable2 = start_prank(ids.OWNER_ADDRESS, target_contract_address=ids.erc20_address)
    %}

    IERC20.approve(contract_address=erc20_address, spender=contract_address, amount=Uint256(100, 0))
    # # this approval does not make sense ?!
    IERC20.approve(contract_address=erc20_address, spender=OWNER_ADDRESS, amount=Uint256(100, 0))

    let (remaining : Uint256) = IERC20.allowance(
        contract_address=erc20_address, owner=OWNER_ADDRESS, spender=contract_address
    )
    local remaining : Uint256 = remaining
    %{
        print(f"owner's remaining.low: {ids.remaining.low}")
        print(f"owner's remaining.high: {ids.remaining.high}")
    %}

    Im_token.approve(
        contract_address=contract_address, spender=OWNER_ADDRESS, amount=Uint256(100, 0)
    )
    # transfer underlying to m_token contract
    Im_token.wrap(contract_address=contract_address, amount=Uint256(10, 0))

    %{
        stop_prank_callable()
        stop_prank_callable2()
    %}
    # # after wrapping token
    let (underlying_balance : Uint256) = IERC20.balanceOf(
        contract_address=erc20_address, account=OWNER_ADDRESS
    )
    local underlying_balance : Uint256 = underlying_balance
    %{
        print(f"[After wrap]owner's underlying_balance.low: {ids.underlying_balance.low}")
        print(f"[After wrap]owner's underlying_balance.high: {ids.underlying_balance.high}")
    %}
    # check remaining underlying balance
    let (is_balance_eq) = uint256_eq(Uint256(999990, 0), underlying_balance)
    assert is_balance_eq = 1
    # check remaining m_token balance

    return ()
end
