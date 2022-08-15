%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256, uint256_eq
from openzeppelin.token.erc20.IERC20 import IERC20

from src.structs.m_token_struct import inflow, outflow

from src.m_token import get_owner, get_underlying_token_addr, wrap
from tests.utils.Im_token import Im_token

const OWNER_ADDRESS = 123456
const RECIPIENT_ADDRESS = 51321332

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

func wrap_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
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

    %{ stop_prank_callable2() %}

    Im_token.approve(
        contract_address=contract_address, spender=OWNER_ADDRESS, amount=Uint256(100, 0)
    )
    # transfer underlying to m_token contract
    Im_token.wrap(contract_address=contract_address, amount=Uint256(10, 0))

    %{ stop_prank_callable() %}
    # check remaining m_token balance

    return ()
end

@external
func test_balance_of{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    wrap_token()

    tempvar erc20_address
    tempvar contract_address
    %{
        ids.contract_address = context.contract_address
        ids.erc20_address = context.erc20_address
        stop_prank_callable = start_prank(ids.OWNER_ADDRESS, target_contract_address=ids.contract_address)
    %}

    let amount_per_second = Uint256(2, 0)
    let deposit_amount = Uint256(5, 0)
    Im_token.start_stream(
        contract_address=contract_address,
        recipient=RECIPIENT_ADDRESS,
        amount_per_second=amount_per_second,
        deposit_amount=deposit_amount,
    )

    %{
        stop_prank_callable()
        stop_prank_callable_recipient = start_prank(ids.RECIPIENT_ADDRESS, target_contract_address=ids.contract_address)
        stop_warp = warp(2, target_contract_address=ids.contract_address)
    %}

    let (balance_after) = Im_token.balance_of(
        contract_address=contract_address, account=RECIPIENT_ADDRESS
    )

    %{ print(f"balance_after.low: {ids.balance_after.low}") %}

    %{ stop_warp() %}
    return ()
end
