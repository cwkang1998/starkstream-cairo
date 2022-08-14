%lang starknet

from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero, assert_lt
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_check,
    uint256_eq,
    uint256_not,
    uint256_add,
    uint256_mul,
    uint256_lt,
    uint256_sub,
)
from src.ERC20_lib import ERC20
from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.access.ownable.library import Ownable
from openzeppelin.security.safemath.library import SafeUint256
from openzeppelin.utils.constants.library import UINT8_MAX
from starkware.starknet.common.syscalls import get_block_timestamp

#
# Storage
#
@storage_var
func underlying_token_addr() -> (address : felt):
end

struct inflow:
    member index : felt
    member amount_per_second : Uint256  # use Uint256
    member created_timestamp : felt
    member to : felt
    member from_sender : felt
    member outflow_index : felt
end

struct outflow:
    member index : felt
    member amount_per_second : Uint256  # use Uint256
    member created_timestamp : felt
    member to : felt
    member from_sender : felt
    member inflow_index : felt
end

# stream_in_length_by_address: account->total len of inflow array
@storage_var
func stream_in_len_by_addr(recipient_addr : felt) -> (res : felt):
end

@storage_var
func stream_in_info_by_addr(recipient_addr : felt, index : felt) -> (res : inflow):
end

@storage_var
func stream_out_len_by_addr(sender_addr : felt) -> (res : felt):
end

@storage_var
func stream_out_info_by_addr(sender_addr : felt, index : felt) -> (res : outflow):
end

@storage_var
func user_last_updated_timestamp(user_addr : felt) -> (timestamp : felt):
end

#
# Contructor
#
@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    name : felt, symbol : felt, owner : felt, token_addr : felt
):
    ERC20.initializer(name, symbol, 18)
    Ownable.initializer(owner)
    underlying_token_addr.write(token_addr)
    return ()
end

#
# Views
#

@view
func name{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (name : felt):
    let (name) = ERC20.name()
    return (name)
end

@view
func symbol{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (symbol : felt):
    let (symbol) = ERC20.symbol()
    return (symbol)
end

@view
func total_supply{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    totalSupply : Uint256
):
    let (totalSupply : Uint256) = ERC20.total_supply()
    return (totalSupply)
end

@view
func decimals{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    decimals : felt
):
    let (decimals) = ERC20.decimals()
    return (decimals)
end

# Static Balance = Initial Balance at latest CRUD timestamp
# Real-Time Balance (dynamic) = Netflow Rate * Seconds elapsed since latest CRUD timestamp
# Current Balance (final) = Static Balance + Real-Time Balance

# need to change logic
@view
func balance_of{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account : felt
) -> (balance : Uint256):
    alloc_locals
    let (balance : Uint256) = ERC20.balance_of(account)
    local balance : Uint256 = balance

    let (in_len) = stream_in_len_by_addr.read(account)
    let (out_len) = stream_out_len_by_addr.read(account)

    # loop here to get all streams
    let (inflow_total_balance) = get_real_time_balance_internal_inflow(
        account, in_len, Uint256(0, 0)
    )
    let (outflow_total_balance) = get_real_time_balance_internal_outflow(
        account, out_len, Uint256(0, 0)
    )

    let (intermediate_balance, add_carry) = uint256_add(balance, inflow_total_balance)
    assert add_carry = 0
    let (final_balance) = uint256_sub(intermediate_balance, outflow_total_balance)
    return (balance=final_balance)
end

func get_real_time_balance_internal_inflow{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(account : felt, stream_len : felt, accumulated_balance : Uint256) -> (res : Uint256):
    if stream_len == 0:
        return (accumulated_balance)
    end

    let (info) = stream_in_info_by_addr.read(account, stream_len - 1)

    # calculate current balance
    let (streamed_amount) = get_streamed_in_amount(info)
    let (new_accumulated, add_carry) = uint256_add(streamed_amount, accumulated_balance)
    assert add_carry = 0

    let (res) = get_real_time_balance_internal_inflow(account, stream_len - 1, new_accumulated)

    return (res=res)
end

func get_real_time_balance_internal_outflow{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(account : felt, stream_len : felt, accumulated_balance : Uint256) -> (res : Uint256):
    if stream_len == 0:
        return (accumulated_balance)
    end

    let (info) = stream_out_info_by_addr.read(account, stream_len - 1)

    # calculate current balance
    let (streamed_amount) = get_streamed_out_amount(info)
    let (new_accumulated, add_carry) = uint256_add(streamed_amount, accumulated_balance)
    assert add_carry = 0

    let (res) = get_real_time_balance_internal_outflow(account, stream_len - 1, new_accumulated)
    return (res=res)
end

func get_streamed_in_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    info : inflow
) -> (res : Uint256):
    alloc_locals
    local start_time

    let (user_last_updated) = user_last_updated_timestamp.read(info.to)
    if user_last_updated == 0:
        start_time = info.created_timestamp
    else:
        start_time = user_last_updated
    end

    let (current_timestamp) = get_block_timestamp()
    let diff = current_timestamp - start_time
    let diff_uint256 = Uint256(diff, 0)
    let (streamed_amount, mul_carry) = uint256_mul(diff_uint256, info.amount_per_second)
    assert mul_carry = Uint256(0, 0)

    # check if sender has enough balance
    # must be from static balance only to prevent infinite loop
    let (sender_balance) = ERC20.balance_of(info.from_sender)

    local final_streamed_amount : Uint256
    let (is_sender_balance_lt_streamed) = uint256_lt(sender_balance, streamed_amount)
    if is_sender_balance_lt_streamed == 1:
        final_streamed_amount.low = sender_balance.low
        final_streamed_amount.high = sender_balance.high
    else:
        final_streamed_amount.low = streamed_amount.low
        final_streamed_amount.high = streamed_amount.high
    end

    return (res=final_streamed_amount)
end

func get_streamed_out_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    info : outflow
) -> (res : Uint256):
    alloc_locals
    local start_time

    let (user_last_updated) = user_last_updated_timestamp.read(info.to)
    if user_last_updated == 0:
        start_time = info.created_timestamp
    else:
        start_time = user_last_updated
    end

    let (current_timestamp) = get_block_timestamp()
    let diff = current_timestamp - start_time
    let diff_uint256 = Uint256(diff, 0)
    let (streamed_amount, mul_carry) = uint256_mul(diff_uint256, info.amount_per_second)
    assert mul_carry = Uint256(0, 0)

    # check if sender has enough balance
    # must be from static balance only to prevent infinite loop
    let (sender_balance) = ERC20.balance_of(info.from_sender)

    local final_streamed_amount : Uint256
    let (is_sender_balance_lt_streamed) = uint256_lt(sender_balance, streamed_amount)
    if is_sender_balance_lt_streamed == 1:
        final_streamed_amount.low = sender_balance.low
        final_streamed_amount.high = sender_balance.high
    else:
        final_streamed_amount.low = streamed_amount.low
        final_streamed_amount.high = streamed_amount.high
    end

    return (res=final_streamed_amount)
end

@view
func allowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt, spender : felt
) -> (remaining : Uint256):
    let (remaining : Uint256) = ERC20.allowance(owner, spender)
    return (remaining)
end

#
# Externals
#

# need to update logic
@external
func transfer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    recipient : felt, amount : Uint256
) -> (success : felt):
    ERC20.transfer(recipient, amount)
    return (1)
end

# need to update logic
@external
func transfer_from{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    sender : felt, recipient : felt, amount : Uint256
) -> (success : felt):
    ERC20.transfer_from(sender, recipient, amount)
    return (1)
end

@external
func approve{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    spender : felt, amount : Uint256
) -> (success : felt):
    ERC20.approve(spender, amount)
    return (1)
end

@external
func increase_allowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    spender : felt, added_value : Uint256
) -> (success : felt):
    ERC20.increase_allowance(spender, added_value)
    return (1)
end

@external
func decreaseAllowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    spender : felt, subtracted_value : Uint256
) -> (success : felt):
    ERC20.decrease_allowance(spender, subtracted_value)
    return (1)
end

#
# Wrapping related logics
#
@external
func wrap{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    to : felt, amount : Uint256
):
    let (token_addr) = underlying_token_addr.read()
    let (caller) = get_caller_address()

    let (transfer_res) = IERC20.transferFrom(
        contract_address=token_addr, sender=caller, recipient=to, amount=amount
    )
    with_attr error_message("Wrapping failed, cannot transfer ERC20 to contract."):
        assert transfer_res = 1
    end

    ERC20._mint(to, amount)
    return ()
end

@external
func unwrap{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account : felt, amount : Uint256
):
    ERC20._burn(account, amount)

    let (token_addr) = underlying_token_addr.read()
    let (m_token_contract) = get_contract_address()
    let (caller) = get_caller_address()

    # update static balance from dynamic

    # user_last_updated_timestamp

    # can just use transfer since sender is this contract
    let (transfer_res) = IERC20.transferFrom(
        contract_address=token_addr, sender=m_token_contract, recipient=caller, amount=amount
    )
    with_attr error_message("Unwrapping failed."):
        assert transfer_res = 1
    end

    return ()
end

@external
func start_stream{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    recipient : felt, amount_per_second : Uint256
):
    let (caller) = get_caller_address()
    let (timestamp_now) = get_block_timestamp()

    let (recipient_len) = stream_in_len_by_addr.read(recipient)
    let (sender_len) = stream_out_len_by_addr.read(caller)
    stream_in_len_by_addr.write(recipient, recipient_len + 1)
    stream_out_len_by_addr.write(caller, sender_len + 1)

    let _inflow = inflow(
        recipient_len, amount_per_second, timestamp_now, recipient, caller, sender_len
    )
    let _outflow = outflow(
        sender_len, amount_per_second, timestamp_now, recipient, caller, recipient_len
    )

    stream_in_info_by_addr.write(recipient, recipient_len, _inflow)
    stream_out_info_by_addr.write(caller, sender_len, _outflow)

    return ()
end

@external
func update_outflow_stream{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    outflow_id : felt, amount_per_second : Uint256
):
    # # struct inflow:
    #     #     member index : felt
    #     #     member amount_per_second : Uint256  # use Uint256
    #     #     member created_timestamp : felt
    #     #     member to : felt
    #     #     member from_sender : felt
    #     # end

    # # struct outflow:
    #     #     member index : felt
    #     #     member amount_per_second : Uint256  # use Uint256
    #     #     member created_timestamp : felt
    #     #     member to : felt
    #     #     member from_sender : felt
    #     # end

    # # # stream_in_length_by_address: account->total len of inflow array
    #     # @storage_var
    #     # func stream_in_len_by_addr(recipient_addr : felt) -> (res : felt):
    #     # end

    # # @storage_var
    #     # func stream_in_info_by_addr(recipient_addr : felt, index : felt) -> (res : inflow):
    #     # end

    # # @storage_var
    #     # func stream_out_len_by_addr(sender_addr : felt) -> (res : felt):
    #     # end

    # # @storage_var
    #     # func stream_out_info_by_addr(sender_addr : felt, index : felt) -> (res : outflow):
    #     # end

    alloc_locals
    let (caller) = get_caller_address()
    let (timestamp_now) = get_block_timestamp()
    
    let (outflow_stream) = stream_out_info_by_addr.read(caller, outflow_id) 
    local outflow_stream: outflow = outflow_stream

    # update static balance of recipient

    let (recipient_dynamic_balance) = balance_of(outflow_stream.to)
    ERC20._overwrite_balance(outflow_stream.to, recipient_dynamic_balance)

    # set recipient update timestamp
    user_last_updated_timestamp.write(outflow_stream.to, timestamp_now)

    # # find inflow and outflow
    # update amount_per_second
    stream_in_info_by_addr.write(
        outflow_stream.to,
        outflow_stream.inflow_index,
        inflow(outflow_stream.inflow_index, amount_per_second, outflow_stream.created_timestamp, outflow_stream.to, caller, outflow_stream.index),
    )
    stream_out_info_by_addr.write(
        caller,
        outflow_stream.index,
        outflow(outflow.index, amount_per_second, outflow_stream.created_timestamp, outflow_stream.to, caller, outflow_stream.inflow_index),
    )

    return ()
end



#### TODO
#- stop_stream
#- unwrap
#- transfer

# output structs
# struct StreamReadInfo
#   member created_timestamp
#   member inflow_index
#   member outflow_index
#   member from_sender
#   member to
#   member amount_per_second

# getter
# - get_all_outflow_streams_by_user(user:felt)
# - get_all_inflow_streams_by_user(user:felt)
# - get_total_outflow_by_user(user:felt)
# - get_total_inflow_by_user(user:felt)




# @external
# func stop_stream{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
#     user_addr : felt, outflow_index : felt
# ):
#     # struct inflow:
#     #     member index : felt
#     #     member amount_per_second : Uint256  # use Uint256
#     #     member created_timestamp : felt
#     #     member to : felt
#     #     member from_sender : felt
#     # end

# # struct outflow:
#     #     member index : felt
#     #     member amount_per_second : Uint256  # use Uint256
#     #     member created_timestamp : felt
#     #     member to : felt
#     #     member from_sender : felt
#     # end

# # # stream_in_length_by_address: account->total len of inflow array
#     # @storage_var
#     # func stream_in_len_by_addr(recipient_addr : felt) -> (res : felt):
#     # end

# # @storage_var
#     # func stream_in_info_by_addr(recipient_addr : felt, index : felt) -> (res : inflow):
#     # end

# # @storage_var
#     # func stream_out_len_by_addr(sender_addr : felt) -> (res : felt):
#     # end

# # @storage_var
#     # func stream_out_info_by_addr(sender_addr : felt, index : felt) -> (res : outflow):
#     # end

# let (_outflow) = stream_out_info_by_addr.read(user_addr, outflow_index)

# # Realize recipient balance before stopping
#     # Change dynamic to static for recipient
#     let (recipient_balance) = balance_of(_outflow.to)

# return ()
# end