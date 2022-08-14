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
from openzeppelin.token.erc20.library import ERC20
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
end

struct outflow:
    member index : felt
    member amount_per_second : Uint256  # use Uint256
    member created_timestamp : felt
    member to : felt
    member from_sender : felt
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

    let _inflow = inflow(recipient_len, amount_per_second, timestamp_now, recipient, caller)
    let _outflow = outflow(sender_len, amount_per_second, timestamp_now, recipient, caller)

    stream_in_info_by_addr.write(recipient, recipient_len, _inflow)
    stream_out_info_by_addr.write(caller, sender_len, _outflow)

    return ()
end

# @external
# func update_stream{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
#     recipient : felt, amount_per_second : Uint256
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

# let (caller) = get_caller_address()
#     let (timestamp_now) = get_block_timestamp()

# # update static balance of recipient
#     let (recipient_dynamic_balance) = get_real_time_balance(recipient)
#     let (current_balance) = ERC20.balance_of(recipient)
#     let (new_balance, add_carry) = uint256_add(current_balance, recipient_dynamic_balance)
#     assert add_carry = 0

# # # TODO

# # set recipient update timestamp
#     user_last_updated_timestamp.write(sender_addr, timestamp_now)

# # find inflow and outflow (how? loop?)
#     # update amount_per_second
#     return ()
# end

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

# Get current net balance
# @view
# func getBalance{
#         syscall_ptr : felt*,
#         pedersen_ptr : HashBuiltin*,
#         range_check_ptr
#     }(account: felt)->(totalBalance:Uint256):
#     # static balance
#     let (static_balance: Uint256)= balance_of(account)

# # dynamic balance

# # inflow
#     let (len_in:felt)= stream_in_len_by_addr.read(account)

# let (inflow_sum: Uint256) = getInflowSum(len_in,stream_in_info_by_addr.read(account))

# # outflow
#     let (len_out:felt)= stream_out_len_by_addr.read(account)
#     let (outflow_sum:Uint256) = getOutflowSum(len_out, stream_out_info_by_addr.read(account))

# let (totalBalance) = static_balance + inflow_sum - outflow_sum
#     return (totalBalance)
# end

# # TODO: modify logic
# @view
# func getInflowSum{
#         syscall_ptr : felt*,
#         pedersen_ptr : HashBuiltin*,
#         range_check_ptr
#     }(n:felt,arr: inflow*)->(res: Uint256):
#     if n==1:
#         let (block_timestamp) = get_block_timestamp()
#         let result= (arr[n-1].amount_per_second*(block_timestamp-arr[n-1].created_timestamp))/86400
#         return (result)
#     end
#     return getInflowSum(n-1,arr[n])

# end
# # TODO: modify logic
# @view
# func getOutflowSum{
#         syscall_ptr : felt*,
#         pedersen_ptr : HashBuiltin*,
#         range_check_ptr
#     }(n:felt,arr: outflow*)->(res: Uint256):
#     if n==1:
#         let (block_timestamp) = get_block_timestamp()
#         let result= (arr[n-1].amount_per_second*(block_timestamp-arr[n-1].created_timestamp))/86400
#         return (result)
#     end
#     return getOutflowSum(n-1,arr[n])
# end

# ######################################################################
# # called by core contract when a new stream is created
# # update sender's outflow and receiver's inflow
# @external
# func Stream_created{
#         syscall_ptr : felt*,
#         pedersen_ptr : HashBuiltin*,
#         range_check_ptr
#     }(sender:felt,receiver:felt,amount:Uint256,created_timestamp:felt)->(bool:felt):
#     # get and update receiver inflow info
#     let (len_in:felt) = stream_in_len_by_addr.read(receiver)

# stream_in_info_by_address.write(receiver,inflow[len_in]=inflow(index= len_in,amount_per_second= amount,created_timestamp=created_timestamp))

# stream_in_len_by_addr.write(receiver,len_in+1)

# # get and update sender outlow info
#     let len_out=stream_out_len_by_addr(sender)
#     stream_out_info_by_addr.write(sender,outflow[len_out]=outflow(index=len_out,amount_per_second= amount,created_timestamp=created_timestamp))

# stream_out_len_by_addr.write(sender,len_out+1)

# return true
# end

# #####################################################################
# # called by core contract when a new stream is stopped
# # update sender's outflow and receiver's inflow
# @external
# func Stream_stopped{
#         syscall_ptr : felt*,
#         pedersen_ptr : HashBuiltin*,
#         range_check_ptr
#     }(sender:felt,receiver:felt,amount:Uint256,created_timestamp:felt)->(bool:felt):
#     # get and update receiver inflow info
#     stream_in_length_by_address: receiver->total len of inflow array
#     let (len_in:felt)= stream_in_len_by_addr.read(receiver)
#     # TODO: change the for loop
#     # for index = range(len_in):
#     #     # a dumb way
#     #     if(stream_in_info_by_addr(receiver)[index].amount_per_second == amount
#     #     && stream_in_info_by_addr(receiver)[index].created_timestamp == created_timestamp)
#     #     let stream_in_info_by_addr(receiver)[index].amount_per_second = 0
#     let (inflow: inflow*) = stream_in_info_by_addr.read(receiver)
#     findInflowStream(len_in,inflow,amount,created_timestamp)
#     # get and update sender outlow info
#     let (len_out:felt)=stream_out_len_by_addr.read(sender)
#     # for index = range(len_out):
#     #     # a dumb way
#     #     if(stream_out_info_by_address(sender)[index].amount_per_second == amount
#     #     && stream_out_info_by_address(sender)[index].created_timestamp == created_timestamp)
#     #     let stream_out_info_by_address(sender)[index].amount_per_second== 0
#     let (outflow: outflow*) = stream_out_info_by_addr.read(sender)
#     findOutflowStream(len_out,outflow,amount,created_timestamp)
#     return true
# end

# @external
# func findInflowStream{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
#     len:Uint256,
#     arr: inflow*,
#     amount: Uint256,
#     created_timestamp: felt
# ):
#     if arr[len-1].amount_per_second == amount && arr[len-1].created_timestamp == created_timestamp:
#         arr[len-1].amount_per_second = 0
#     end
#     return findInflowStream(len-1,arr,amount,created_timestamp)
# end
# @external
# func findOutflowStream{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
#     len:Uint256,
#     arr: outflow*,
#     amount: Uint256,
#     created_timestamp: felt
# ):
#     if arr[len-1].amount_per_second == amount && arr[len-1].created_timestamp == created_timestamp:
#         arr[len-1].amount_per_second = 0
#     end
#     return findOutflowStream(len-1,arr,amount,created_timestamp)
# end
# ####################################################################################

# #TODO: consider negative part
