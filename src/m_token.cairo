%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_lt
from starkware.starknet.common.syscalls import get_block_timestamp, get_caller_address, get_contract_address
from src.structs.m_token_struct import inflow, outflow
from src.ERC20_lib import ERC20
from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.access.ownable.library import Ownable
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_check,
    uint256_eq,
    uint256_not,
    uint256_add,
    uint256_mul,
    uint256_lt,
    uint256_le,
    uint256_sub,
)

@storage_var
func underlying_token_addr() -> (address : felt):
end

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

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    name : felt, symbol : felt, owner : felt, token_addr : felt
):
    ERC20.initializer(name, symbol, 18)
    Ownable.initializer(owner)
    underlying_token_addr.write(token_addr)
    return ()
end

@view
func get_underlying_token_addr{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr,
    }() -> (res:felt):
    let (token_addr) = underlying_token_addr.read()
    return (res=token_addr)
end

@view
func get_owner{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr,
    }() -> (owner:felt):
    let (res) = Ownable.owner()
    return (owner=res)
end

@view
func name{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (name:felt):
    let (name) = ERC20.name()
    return (name)
end

@view
func symbol{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (symbol:felt):
    let (symbol) = ERC20.symbol()
    return (symbol)
end

@view
func total_supply{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() ->(total_supply : Uint256):
    let (total_supply) = ERC20.total_supply()
    return (total_supply)
end

@view
func decimals{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (decimals:felt):
    let (decimals) = ERC20.decimals()
    return (decimals)
end

@view 
func balance_of{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account: felt
) -> (balance: Uint256):
    # static balance + dynamic balanc
    alloc_locals
    let (balance : Uint256) = ERC20.balance_of(account)
    local balance : Uint256 = balance

    let (in_len) = stream_in_len_by_addr.read(account)

    # loop here to get all streams
    let (inflow_total_balance) = get_real_time_balance_internal_inflow(
        account, in_len, Uint256(0, 0)
    )

    let (final_balance, add_carry) = uint256_add(balance, inflow_total_balance)
    assert add_carry = 0
    return (balance=final_balance)
end

@external
func approve{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(spender: felt, amount: Uint256):
    ERC20.approve(spender, amount)
    return ()
end

@view
func allowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        owner : felt, spender : felt
    ) -> (remaining : Uint256):

    let (res) = ERC20.allowance(owner, spender)
    return (res)
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

    # check if deposit has enough balance
    let deposit_balance = info.deposit

    local final_streamed_amount : Uint256
    let (is_deposit_balance_lt_streamed) = uint256_lt(deposit_balance, streamed_amount)
    if is_deposit_balance_lt_streamed == 1:
        final_streamed_amount.low = deposit_balance.low
        final_streamed_amount.high = deposit_balance.high
    else:
        final_streamed_amount.low = streamed_amount.low
        final_streamed_amount.high = streamed_amount.high
    end

    return (res=final_streamed_amount)
end

@external 
func wrap{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    amount : Uint256
):
    let (token_addr) = underlying_token_addr.read()
    let (caller) = get_caller_address()
    let (this_contract) = get_contract_address()

    let (transfer_res) = IERC20.transferFrom(
        contract_address=token_addr, sender=caller, recipient=this_contract, amount=amount
    )
    with_attr error_message("Wrapping failed, cannot transfer ERC20 to contract."):
        assert transfer_res = 1
    end

    ERC20._mint(caller, amount)
    return ()
end

@external
func unwrap{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    amount: Uint256
):
    alloc_locals
    let (caller) = get_caller_address()
    local caller = caller

    let (this_contract) = get_contract_address()
    let (token_addr) = underlying_token_addr.read()

    update_static_balance_from_internal(caller)

    ERC20._burn(caller, amount)

    let (transfer_res) = IERC20.transfer(
        contract_address=token_addr, recipient=caller, amount=amount
    )
    with_attr error_message("Unwrapping failed."):
        assert transfer_res = 1
    end

    return ()
end

@external
func start_stream{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    recipient : felt, amount_per_second : Uint256, deposit_amount: Uint256
):
    alloc_locals
    let (caller) = get_caller_address()
    let (timestamp_now) = get_block_timestamp()

    let (recipient_len) = stream_in_len_by_addr.read(recipient)
    let (sender_len) = stream_out_len_by_addr.read(caller)
    local recipient_len = recipient_len
    local sender_len = sender_len

    stream_in_len_by_addr.write(recipient, recipient_len + 1)
    stream_out_len_by_addr.write(caller, sender_len + 1)

    # transfer mToken from user to this contract address, this will be our deposit
    let (this_contract) = get_contract_address()
    ERC20.transfer_from(caller, this_contract, deposit_amount)

    let _inflow = inflow(
        recipient_len, amount_per_second, timestamp_now, recipient, caller, sender_len, deposit_amount
    )
    let _outflow = outflow(
        sender_len, amount_per_second, timestamp_now, recipient, caller, recipient_len, deposit_amount
    )

    stream_in_info_by_addr.write(recipient, recipient_len, _inflow)
    stream_out_info_by_addr.write(caller, sender_len, _outflow)

    return ()
end

@external 
func update_stream{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    outflow_id : felt, amount_per_second : Uint256
):
    alloc_locals
    let (caller) = get_caller_address()

    let (outflow_stream) = stream_out_info_by_addr.read(caller, outflow_id)

    # update static balance of recipient
    update_static_balance_from_internal(outflow_stream.to)

    # get outflow after static balance update (deposit has changed)
    let (outflow_stream) = stream_out_info_by_addr.read(caller, outflow_id)
    local outflow_stream : outflow = outflow_stream

    # # find inflow and outflow
    # update amount_per_second
    stream_in_info_by_addr.write(
        outflow_stream.to,
        outflow_stream.inflow_index,
        inflow(outflow_stream.inflow_index, amount_per_second, outflow_stream.created_timestamp, outflow_stream.to, caller, outflow_stream.index, outflow_stream.deposit),
    )
    stream_out_info_by_addr.write(
        caller,
        outflow_stream.index,
        outflow(outflow.index, amount_per_second, outflow_stream.created_timestamp, outflow_stream.to, caller, outflow_stream.inflow_index, outflow_stream.deposit),
    )

    return ()
end

func update_static_balance_from_internal{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    recipient: felt
):
    let (recipient_len) = stream_in_len_by_addr.read(recipient)
    update_static_balance_from_internal_loop(recipient, recipient_len)

    # set recipient update timestamp
    let (timestamp_now) = get_block_timestamp()
    user_last_updated_timestamp.write(recipient, timestamp_now)

    return ()
end

func update_static_balance_from_internal_loop{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    recipient: felt, total_len: felt
):
    alloc_locals
    if total_len == 0:
        return ()
    end

    let (inflow_info) = stream_in_info_by_addr.read(recipient, total_len-1)
    local inflow_info: inflow = inflow_info

    let (streamed_amount) = get_streamed_in_amount(inflow_info)
    let (this_contract) = get_contract_address()

    ERC20._transfer(this_contract, recipient, streamed_amount)

    let (remaining_deposit) = uint256_sub(inflow_info.deposit, streamed_amount)

    let new_inflow_info = inflow(inflow_info.index, 
                                 inflow_info.amount_per_second, 
                                 inflow_info.created_timestamp, 
                                 inflow_info.to, 
                                 inflow_info.from_sender, 
                                 inflow_info.outflow_index,
                                 remaining_deposit)
    let new_outflow_info = outflow(
                            inflow_info.outflow_index,
                            inflow_info.amount_per_second, 
                            inflow_info.created_timestamp, 
                            inflow_info.to, 
                            inflow_info.from_sender, 
                            inflow_info.index,
                            remaining_deposit)

    stream_in_info_by_addr.write(
        inflow_info.to,
        inflow_info.index,
        new_inflow_info,
    )
    stream_out_info_by_addr.write(
        inflow_info.from_sender,
        inflow_info.outflow_index,
        new_outflow_info,
    )

    update_static_balance_from_internal_loop(recipient, total_len-1)
    return ()
end

@external
func sender_remove_deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    outflow_id: felt, to_remove_amount: Uint256
):
    alloc_locals
    let (caller) = get_caller_address()
    local caller = caller

    assert_valid_out_stream(caller, outflow_id)
    
    let (outflow_info) = stream_out_info_by_addr.read(caller, outflow_id)

    update_static_balance_from_internal(outflow_info.to)
    
    # fetch again after update
    let (outflow_info) = stream_out_info_by_addr.read(caller, outflow_id)
    let (is_enough_deposit_to_remove) = uint256_le(to_remove_amount, outflow_info.deposit)
    assert is_enough_deposit_to_remove = 1

    let (this_contract) = get_contract_address()
    ERC20._transfer(this_contract, caller, to_remove_amount)
    let (new_deposit) = uint256_sub(outflow_info.deposit, to_remove_amount)


    let new_inflow = inflow(outflow_info.inflow_index, outflow_info.amount_per_second, 
                            outflow_info.created_timestamp, outflow_info.to, 
                            outflow_info.from_sender, outflow_info.index, 
                            new_deposit)
    let new_outflow = outflow(outflow_info.index, outflow_info.amount_per_second, 
                            outflow_info.created_timestamp, outflow_info.to, 
                            outflow_info.from_sender, outflow_info.inflow_index, 
                            new_deposit)

    stream_out_info_by_addr.write(caller, outflow_id, new_outflow)
    stream_in_info_by_addr.write(outflow_info.to, outflow_info.inflow_index, new_inflow)

    return ()
end

@external
func sender_add_deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    outflow_id: felt, to_add_amount: Uint256
):
    alloc_locals
    let (caller) = get_caller_address()
    local caller = caller

    assert_valid_out_stream(caller, outflow_id)
    
    let (outflow_info) = stream_out_info_by_addr.read(caller, outflow_id)

    let (this_contract) = get_contract_address()
    ERC20.transfer_from(caller, this_contract, to_add_amount)
    let (new_deposit, add_carry) = uint256_add(outflow_info.deposit, to_add_amount)
    assert add_carry = 0


    let new_inflow = inflow(outflow_info.inflow_index, outflow_info.amount_per_second, 
                            outflow_info.created_timestamp, outflow_info.to, 
                            outflow_info.from_sender, outflow_info.index, 
                            new_deposit)
    let new_outflow = outflow(outflow_info.index, outflow_info.amount_per_second, 
                            outflow_info.created_timestamp, outflow_info.to, 
                            outflow_info.from_sender, outflow_info.inflow_index, 
                            new_deposit)

    stream_out_info_by_addr.write(caller, outflow_id, new_outflow)
    stream_in_info_by_addr.write(outflow_info.to, outflow_info.inflow_index, new_inflow)

    return ()
end

@external
func cancel_stream{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    outflow_id: felt
):
    alloc_locals
    let (caller) = get_caller_address()
    local caller = caller

    assert_valid_out_stream(caller, outflow_id)
    
    # update recipient static balance
    let (outflow_info) = stream_out_info_by_addr.read(caller, outflow_id)
    update_static_balance_from_internal(outflow_info.to)

    let (outflow_len) = stream_out_len_by_addr.read(caller)
    let (outflow_info) = stream_out_info_by_addr.read(caller, outflow_id)

    # refund caller
    let (this_contract) = get_contract_address()
    ERC20._transfer(this_contract, caller, outflow_info.deposit)

    let (inflow_len) = stream_in_len_by_addr.read(outflow_info.to)

    let (last_outflow) = stream_out_info_by_addr.read(caller, outflow_len-1)
    let (last_inflow) = stream_in_info_by_addr.read(outflow_info.to, inflow_len-1)

    # swap last outflow to the deleted outflow position
    # get inflow associated to last outflow and update the outflow index
    let (associated_inflow) = stream_in_info_by_addr.read(last_outflow.to, last_outflow.inflow_index)
    let new_associated_inflow = inflow(associated_inflow.index, associated_inflow.amount_per_second, 
                                            associated_inflow.created_timestamp, associated_inflow.to, 
                                            associated_inflow.from_sender, outflow_id, 
                                            associated_inflow.deposit)

    stream_in_info_by_addr.write(last_outflow.to, last_outflow.inflow_index, new_associated_inflow)

    stream_out_info_by_addr.write(caller, outflow_id,
        outflow(outflow_id, last_outflow.amount_per_second, last_outflow.created_timestamp, 
        last_outflow.to, last_outflow.from_sender, last_outflow.inflow_index, 
        last_outflow.deposit)
    )
    stream_out_len_by_addr.write(caller, outflow_len-1)

    # swap last input to the deleted inflow position
    let (associated_outflow) = stream_out_info_by_addr.read(last_inflow.from_sender, last_inflow.outflow_index)
    let new_associated_outflow = outflow(associated_outflow.index, associated_outflow.amount_per_second, 
    associated_outflow.created_timestamp, associated_outflow.to, 
    associated_outflow.from_sender, outflow_info.inflow_index, 
    associated_outflow.deposit)

    stream_out_info_by_addr.write(last_inflow.from_sender, last_inflow.outflow_index, new_associated_outflow)

    stream_in_info_by_addr.write(outflow_info.to, outflow_info.inflow_index,
        inflow(outflow_info.inflow_index, last_inflow.amount_per_second, last_inflow.created_timestamp,
        last_inflow.to, last_inflow.from_sender, last_inflow.outflow_index,
        last_inflow.deposit)
    )
    stream_in_len_by_addr.write(outflow_info.to, inflow_len-1)

    return ()
end


func assert_valid_out_stream{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    sender:felt, outflow_id: felt
):
    let (len) = stream_out_len_by_addr.read(sender)
    assert_lt(outflow_id, len)

    return ()
end

@external
func transfer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    recipient: felt, amount: Uint256
):
    let (caller) = get_caller_address()
    update_static_balance_from_internal(caller)

    ERC20.transfer(recipient, amount)

    return ()
end

@external
func transfer_from{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        sender : felt, recipient : felt, amount : Uint256
    ): 

    update_static_balance_from_internal(sender)
    ERC20.transfer_from(sender, recipient, amount)
    return ()
end

@view
func get_all_outflow_streams_by_user{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    user: felt
) -> (res_len: felt, res: outflow*):
    let (outflow_len) = stream_out_len_by_addr.read(user)
    let (outflows: outflow*) = alloc()
    let (res_len, res) = get_all_outflow_streams_by_user_internal(user, outflow_len, 0, 0, outflows)

    return (res_len, res)
end

func get_all_outflow_streams_by_user_internal{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    sender: felt, total_length: felt, current_index: felt, res_len: felt, res: outflow*
) -> (res_len: felt, res: outflow*):
    if total_length == 0:
        return (res_len, res)
    end

    let (outflow_info) = stream_out_info_by_addr.read(sender, current_index)
    assert res[current_index] = outflow_info

    let (outflows_len, outflows) = get_all_outflow_streams_by_user_internal(sender, total_length-1, current_index+1, res_len+1, res)

    return (outflows_len, outflows)
end

@view
func get_all_inflow_streams_by_user{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    user: felt
) -> (res_len: felt, res: inflow*):
    let (inflow_len) = stream_in_len_by_addr.read(user)
    let (inflows: inflow*) = alloc()

    let (res_len, res) = get_all_inflow_streams_by_user_internal(user, inflow_len, 0, 0, inflows)

    return (res_len, res)
end

func get_all_inflow_streams_by_user_internal{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    sender: felt, total_length: felt, current_index: felt, res_len: felt, res: inflow*
) -> (res_len: felt, res: inflow*):
    if total_length == 0:
        return (res_len, res)
    end

    let (inflow_info) = stream_in_info_by_addr.read(sender, current_index)
    assert res[current_index] = inflow_info

    let (inflows_len, inflows) = get_all_inflow_streams_by_user_internal(sender, total_length-1, current_index+1, res_len+1, res)

    return (inflows_len, inflows)
end

